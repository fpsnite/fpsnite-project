"""Password hashing and credential verification (PBKDF2-HMAC-SHA256).

Format stored in the DB: pbkdf2$<iterations>$<salt_hex>$<hash_hex>.
"""
import hashlib
import hmac
import os
import secrets

_ITERATIONS = 600_000
_SALT_BYTES = 16


def hash_password(password: str) -> str:
    salt = os.urandom(_SALT_BYTES)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, _ITERATIONS)
    return f"pbkdf2${_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        scheme, iterations, salt_hex, hash_hex = stored.split("$")
        assert scheme == "pbkdf2"
        salt = bytes.fromhex(salt_hex)
        expected = bytes.fromhex(hash_hex)
    except (ValueError, AssertionError):
        return False
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, int(iterations))
    return hmac.compare_digest(digest, expected)


def generate_token() -> str:
    """Raw token shown to the user exactly once. Keep it server-side only."""
    return secrets.token_urlsafe(32)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()