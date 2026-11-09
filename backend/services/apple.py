"""Проверка Apple identity token на сервере (подпись, issuer, audience, срок)."""
import jwt
from django.conf import settings

APPLE_ISSUER = "https://appleid.apple.com"
APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys"

_jwks_client = None


class AppleTokenError(Exception):
    pass


def _client():
    global _jwks_client
    if _jwks_client is None:
        _jwks_client = jwt.PyJWKClient(APPLE_KEYS_URL, cache_keys=True, lifespan=3600, timeout=10)
    return _jwks_client


def verify_identity_token(token: str) -> dict:
    """Возвращает claims (sub, email?) или бросает AppleTokenError."""
    try:
        signing_key = _client().get_signing_key_from_jwt(token)
        return jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=settings.APPLE_BUNDLE_ID,
            issuer=APPLE_ISSUER,
            options={"require": ["sub", "exp", "iat"]},
        )
    except (jwt.PyJWTError, jwt.PyJWKClientError) as exc:
        raise AppleTokenError(type(exc).__name__) from exc
