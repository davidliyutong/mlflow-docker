# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#   "requests",
# ]
# ///

"""End-to-end smoke test for the OIDC-enabled stack.

Runs inside the compose network (see docker-compose.oidc.yml, service
`oidc-smoke`) so that the identity provider is reachable under the same
hostname the MLflow server uses for OIDC discovery: Keycloak derives the
token issuer from the request host, and issuer validation fails when the
browser-side and server-side hostnames differ.

Verifies, in order:
  1. unauthenticated requests are rejected and /login redirects to the IdP
  2. full authorization-code (+PKCE) login for a user in the allowed group
  3. access token (PAT) creation, then the full training smoke through the
     mlflow client using basic auth
  4. admin-group login can list users, the same call is denied to the user
  5. a user outside the allowed groups cannot establish a session
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from http.cookiejar import DefaultCookiePolicy
from pathlib import Path

import requests

# Keycloak marks its session cookies Secure (SameSite=None) even over plain
# HTTP. Browsers exempt localhost from that rule, requests does not, so allow
# Secure cookies over HTTP for this test harness.
DefaultCookiePolicy.return_ok_secure = lambda self, cookie, request: True

USERNAME = "mlflow-user@example.com"
USER_PASSWORD = "mlflow-user-password"
ADMIN_USERNAME = "mlflow-admin@example.com"
ADMIN_PASSWORD = "mlflow-admin-password"
OUTSIDER_USERNAME = "outsider@example.com"
OUTSIDER_PASSWORD = "outsider-password"


def wait_for_server(mlflow_uri: str, timeout_seconds: int) -> None:
    deadline = time.time() + timeout_seconds
    last_error = None

    while time.time() < deadline:
        try:
            response = requests.get(f"{mlflow_uri}/health/ready", timeout=5)
            if response.status_code == 200:
                return
            last_error = f"HTTP {response.status_code}: {response.text[:160]}"
        except Exception as exc:
            last_error = exc
        time.sleep(2)

    raise RuntimeError(f"MLflow server was not ready at {mlflow_uri}: {last_error}")


def check_unauthenticated(mlflow_uri: str) -> None:
    response = requests.get(
        f"{mlflow_uri}/api/2.0/mlflow/experiments/search", timeout=10
    )
    if response.status_code != 401:
        raise RuntimeError(
            f"Unauthenticated API call expected 401, got {response.status_code}: "
            f"{response.text[:200]}"
        )

    response = requests.get(f"{mlflow_uri}/login", allow_redirects=False, timeout=10)
    if response.status_code not in (301, 302, 303, 307, 308):
        raise RuntimeError(f"/login expected a redirect, got {response.status_code}")
    location = response.headers.get("Location", "")
    if "openid-connect/auth" not in location or "code_challenge=" not in location:
        raise RuntimeError(f"/login redirect is not an OIDC PKCE flow: {location}")


def parse_login_form(html: str) -> tuple[str, dict[str, str]]:
    form = re.search(r'<form[^>]+action="([^"]+)"', html)
    if not form:
        raise RuntimeError("Keycloak login form not found in the response")
    action = form.group(1).replace("&amp;", "&")

    data = {}
    for field in re.findall(r"<input[^>]*>", html):
        if "hidden" not in field:
            continue
        name = re.search(r'name="([^"]+)"', field)
        if name:
            value = re.search(r'value="([^"]*)"', field)
            data[name.group(1)] = value.group(1) if value else ""
    return action, data


def oidc_login(mlflow_uri: str, username: str, password: str) -> requests.Session:
    session = requests.Session()
    response = session.get(f"{mlflow_uri}/login", allow_redirects=False, timeout=10)
    response.raise_for_status()
    provider_url = response.headers["Location"]

    response = session.get(provider_url, timeout=15)
    response.raise_for_status()
    action, data = parse_login_form(response.text)
    data["username"] = username
    data["password"] = password
    session.post(action, data=data, allow_redirects=True, timeout=15)
    return session


def auth_status(session: requests.Session, mlflow_uri: str) -> dict | None:
    response = session.get(f"{mlflow_uri}/auth/status", timeout=10)
    if response.status_code != 200:
        return None
    return response.json()


def require_authenticated(session: requests.Session, mlflow_uri: str, expected: str) -> None:
    status = auth_status(session, mlflow_uri)
    if not status or status.get("authenticated") is not True:
        raise RuntimeError(f"Login did not establish a session: {status}")
    if status.get("username") != expected:
        raise RuntimeError(f"Expected username {expected!r}, got {status.get('username')!r}")


def create_personal_access_token(session: requests.Session, mlflow_uri: str) -> str:
    # PATCH replaces the caller's `default` token, keeping repeated smoke runs
    # idempotent (POST would hit the per-user token cap over time).
    expiration = (datetime.now(timezone.utc) + timedelta(days=7)).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    response = session.patch(
        f"{mlflow_uri}/api/2.0/mlflow/users/access-token",
        json={"expiration": expiration},
        timeout=10,
    )
    if response.status_code != 200:
        raise RuntimeError(
            f"Token creation failed with {response.status_code}: {response.text[:300]}"
        )
    token = response.json().get("token")
    if not token:
        raise RuntimeError(f"Token creation returned no token: {response.text[:300]}")
    return token


def run_training_smoke(mlflow_uri: str, username: str, token: str, experiment: str) -> dict:
    script = Path(__file__).with_name("mlflow_training_smoke.py")
    env = {
        **os.environ,
        "MLFLOW_TRACKING_USERNAME": username,
        "MLFLOW_TRACKING_PASSWORD": token,
    }
    env.pop("MLFLOW_TRACKING_TOKEN", None)

    result = subprocess.run(
        [
            sys.executable,
            str(script),
            "--tracking-uri",
            mlflow_uri,
            "--experiment",
            experiment,
        ],
        env=env,
        capture_output=True,
        text=True,
        timeout=180,
    )
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        raise RuntimeError(f"Training smoke failed with exit code {result.returncode}")

    match = re.search(r"\n\{.*\}\s*$", result.stdout, re.DOTALL)
    return json.loads(match.group(0)) if match else {}


def check_admin_access(mlflow_uri: str) -> str:
    admin_session = oidc_login(mlflow_uri, ADMIN_USERNAME, ADMIN_PASSWORD)
    require_authenticated(admin_session, mlflow_uri, ADMIN_USERNAME)

    response = admin_session.get(
        f"{mlflow_uri}/api/2.0/mlflow/users/{USERNAME}", timeout=10
    )
    if response.status_code != 200 or USERNAME not in response.text:
        raise RuntimeError(
            f"Admin profile read expected 200 mentioning {USERNAME!r}, got "
            f"{response.status_code}: {response.text[:200]}"
        )
    return ADMIN_USERNAME


def check_group_restriction(mlflow_uri: str) -> None:
    session = oidc_login(mlflow_uri, OUTSIDER_USERNAME, OUTSIDER_PASSWORD)
    if auth_status(session, mlflow_uri) is not None:
        raise RuntimeError("A login outside the allowed groups established a session")


def check_non_admin_denied(session: requests.Session, mlflow_uri: str) -> None:
    # Reading another user's profile is admin-only.
    response = session.get(
        f"{mlflow_uri}/api/2.0/mlflow/users/{ADMIN_USERNAME}", timeout=10
    )
    if response.status_code != 403:
        raise RuntimeError(
            f"Non-admin profile read expected 403, got {response.status_code}: "
            f"{response.text[:200]}"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mlflow-uri", default="http://mlflow:8080")
    parser.add_argument("--keycloak-uri", default="http://keycloak:8180")
    parser.add_argument("--experiment", default="oidc-smoke")
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()

    wait_for_server(args.mlflow_uri, args.timeout)
    check_unauthenticated(args.mlflow_uri)

    user_session = oidc_login(args.mlflow_uri, USERNAME, USER_PASSWORD)
    require_authenticated(user_session, args.mlflow_uri, USERNAME)
    check_non_admin_denied(user_session, args.mlflow_uri)

    token = create_personal_access_token(user_session, args.mlflow_uri)
    training = run_training_smoke(args.mlflow_uri, USERNAME, token, args.experiment)

    admin = check_admin_access(args.mlflow_uri)
    check_group_restriction(args.mlflow_uri)

    print(
        json.dumps(
            {
                "mlflow_uri": args.mlflow_uri,
                "keycloak_uri": args.keycloak_uri,
                "authenticated_user": USERNAME,
                "admin_user": admin,
                "group_restriction_enforced": True,
                "training_run_id": training.get("run_id"),
                "training_artifacts_verified": training.get("verified_artifact_count"),
                "training_final_loss": training.get("final_loss"),
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
