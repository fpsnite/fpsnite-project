"""Structured API errors: HTTP status + machine-readable code + message."""
from typing import Any


class ErrorCodes:
    INVALID_USERNAME = "INVALID_USERNAME"
    INVALID_PASSWORD = "INVALID_PASSWORD"
    INVALID_CREDENTIALS = "INVALID_CREDENTIALS"
    NAME_TAKEN = "NAME_TAKEN"
    MISSING_TOKEN = "MISSING_TOKEN"
    INVALID_TOKEN = "INVALID_TOKEN"
    NOT_FOUND = "NOT_FOUND"
    FORBIDDEN = "FORBIDDEN"
    ALREADY_FRIENDS = "ALREADY_FRIENDS"
    FRIEND_NOT_FOUND = "FRIEND_NOT_FOUND"
    INSUFFICIENT_COINS = "INSUFFICIENT_COINS"
    INVALID_SKIN = "INVALID_SKIN"
    SKIN_NOT_OWNED = "SKIN_NOT_OWNED"


class APIError(Exception):
    """Raised in services; converted to an HTTP 4xx by the route layer."""

    def __init__(self, code: str, message: str, status_code: int = 400, extra: Any | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.extra = extra