"""Operator-only initial administrator bootstrap; no built-in/default credentials."""

import argparse
import getpass
import sys
from pathlib import Path

from pydantic import ValidationError
from pydantic_settings import PydanticBaseSettingsSource
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError

from app.core.config import Environment, Settings
from app.core.database import create_session_factory
from app.models.identity import Role, User
from app.schemas.auth import RegisterRequest, SessionMode
from app.services.access import audit, lock_identity
from app.services.auth import PASSWORDS


class OperatorSettings(Settings):
    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls,
        init_settings: PydanticBaseSettingsSource,
        env_settings,
        dotenv_settings,
        file_secret_settings,
    ):
        # An exported shell DATABASE_URL must not redirect an explicit environment.
        return init_settings, dotenv_settings


def bootstrap(db, payload: RegisterRequest):
    lock_identity(db)
    if db.scalar(select(User.id).where(User.role == Role.SUPER_ADMIN)):
        raise ValueError("A super administrator already exists; use the authenticated role API")
    if db.scalar(select(User.id).where(User.email == payload.email)):
        raise ValueError("An account already uses this email; no existing account was modified")
    user = User(
        email=payload.email,
        display_name=payload.display_name,
        role=Role.SUPER_ADMIN,
        password_hash=PASSWORDS.hash(payload.password.get_secret_value()),
    )
    db.add(user)
    db.flush()
    audit(db, user.id, "super_admin_bootstrapped", user.id)
    db.commit()
    return user.id


def main():
    parser = argparse.ArgumentParser(
        description="Create the first super administrator on the server"
    )
    parser.add_argument("--environment", choices=list(Environment), required=True)
    parser.add_argument("--email", required=True)
    parser.add_argument("--display-name", required=True)
    parser.add_argument(
        "--password-stdin",
        action="store_true",
        help="Read one password line from a private pipe; never pass it as an argument",
    )
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    env_file = (
        root
        / {"local": ".env", "staging": ".env.staging", "production": ".env.production"}[
            args.environment
        ]
    )
    try:
        if not env_file.is_file():
            raise ValueError("The selected environment file does not exist")
        settings = OperatorSettings(_env_file=env_file)
        if settings.app_env != args.environment:
            raise ValueError("Environment file does not match the requested environment")
        if args.password_stdin:
            password = sys.stdin.readline(1024).removesuffix("\n").removesuffix("\r")
        else:
            password = getpass.getpass("New password (15–128 characters): ")
            if password != getpass.getpass("Confirm password: "):
                raise ValueError("Passwords do not match")
        payload = RegisterRequest(
            email=args.email,
            display_name=args.display_name,
            password=password,
            session_mode=SessionMode.BEARER,
        )
        factory = create_session_factory(settings)
        try:
            with factory() as db:
                user_id = bootstrap(db, payload)
        finally:
            factory.kw["bind"].dispose()
    except (ValueError, ValidationError, SQLAlchemyError, OSError, EOFError):
        parser.exit(
            1,
            "Administrator creation failed. "
            "Check the selected environment, input and existing accounts.\n",
        )
    print(f"Initial super administrator created: {user_id}")


if __name__ == "__main__":
    main()
