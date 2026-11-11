"""Проверка Google ID token на сервере (подпись, issuer, audience, срок, nonce, подтверждённый email).

Приложение передаёт Google SHA-256 от случайного nonce, а серверу — сам nonce (как у Apple):
перехваченный токен без совпадающего nonce не принимается.
"""
import hashlib
import hmac

import jwt
from django.conf import settings

GOOGLE_ISSUERS = ("https://accounts.google.com", "accounts.google.com")
GOOGLE_KEYS_URL = "https://www.googleapis.com/oauth2/v3/certs"

_jwks_client = None


class GoogleTokenError(Exception):
    pass


def is_configured() -> bool:
    return bool(settings.GOOGLE_CLIENT_IDS)


def _client():
    global _jwks_client
    if _jwks_client is None:
        _jwks_client = jwt.PyJWKClient(GOOGLE_KEYS_URL, cache_keys=True, lifespan=3600, timeout=10)
    return _jwks_client


def verify_id_token(token: str, raw_nonce: str) -> dict:
    if not is_configured():
        raise GoogleTokenError("not_configured")
    if not raw_nonce:
        raise GoogleTokenError("missing_nonce")
    try:
        signing_key = _client().get_signing_key_from_jwt(token)
        claims = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=list(settings.GOOGLE_CLIENT_IDS),
            options={"require": ["sub", "exp", "iat", "iss", "nonce"]},
        )
    except (jwt.PyJWTError, jwt.PyJWKClientError) as exc:
        raise GoogleTokenError(type(exc).__name__) from exc
    if claims.get("iss") not in GOOGLE_ISSUERS:
        raise GoogleTokenError("bad_issuer")
    expected = hashlib.sha256(raw_nonce.encode()).hexdigest()
    if not hmac.compare_digest(str(claims.get("nonce", "")), expected):
        raise GoogleTokenError("nonce_mismatch")
    return claims
