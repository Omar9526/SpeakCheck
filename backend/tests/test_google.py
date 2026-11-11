"""Вход через Google: подпись, audience, issuer, nonce и перенос данных гостя."""
import hashlib
import time
from types import SimpleNamespace
from unittest import mock

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from rest_framework.test import APIClient

from apps.accounts.models import User
from services import google

CLIENT_ID = "123-abc.apps.googleusercontent.com"


@pytest.fixture
def google_key(settings):
    settings.GOOGLE_CLIENT_IDS = (CLIENT_ID,)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    with mock.patch.object(google, "_client") as client:
        client.return_value.get_signing_key_from_jwt.return_value = SimpleNamespace(key=key.public_key())
        yield key


def _token(key, **overrides):
    claims = {"iss": "https://accounts.google.com", "aud": CLIENT_ID, "sub": "google-sub-1",
              "iat": int(time.time()), "exp": int(time.time()) + 600,
              "nonce": hashlib.sha256(b"raw-nonce").hexdigest()}
    claims.update(overrides)
    return jwt.encode(claims, key, algorithm="RS256")


def _post(client, token, nonce="raw-nonce"):
    return client.post("/api/v1/auth/google", {"id_token": token, "nonce": nonce}, format="json")


def test_valid_token_creates_account(google_key, transactional_db):
    r = _post(APIClient(), _token(google_key))
    assert r.status_code == 200 and r.data["access"]
    assert User.objects.get(google_sub="google-sub-1").is_guest is False


def test_short_issuer_form_accepted(google_key, transactional_db):
    assert _post(APIClient(), _token(google_key, iss="accounts.google.com")).status_code == 200


def test_guest_becomes_google_account(api, user, document, google_key):
    r = _post(api, _token(google_key))
    assert r.status_code == 200
    user.refresh_from_db()
    assert user.google_sub == "google-sub-1" and user.is_guest is False and user.documents.count() == 1


def test_guest_merged_into_existing_google_account(api, user, document, google_key):
    existing = User.objects.create_user(google_sub="google-sub-1")
    r = _post(api, _token(google_key))
    assert r.status_code == 200 and r.data["user"]["id"] == str(existing.id)
    assert existing.documents.count() == 1
    assert not User.objects.filter(id=user.id).exists()


def test_google_and_apple_are_separate_accounts(google_key, transactional_db):
    apple_user = User.objects.create_user(apple_sub="google-sub-1")
    r = _post(APIClient(), _token(google_key))
    assert r.data["user"]["id"] != str(apple_user.id)


@pytest.mark.parametrize("overrides,nonce", [
    ({"aud": "999-attacker.apps.googleusercontent.com"}, "raw-nonce"),  # токен для чужого приложения
    ({"iss": "https://evil.example.com"}, "raw-nonce"),                 # чужой издатель
    ({"exp": int(time.time()) - 10}, "raw-nonce"),                      # просрочен
    ({}, "other-nonce"),                                                 # перехваченный токен
    ({}, ""),                                                            # nonce не передан
])
def test_bad_tokens_rejected(google_key, transactional_db, overrides, nonce):
    r = _post(APIClient(), _token(google_key, **overrides), nonce)
    assert r.status_code in (400, 401)
    assert not User.objects.filter(google_sub="google-sub-1").exists()


def test_token_signed_by_other_key_rejected(google_key, transactional_db):
    other = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    r = _post(APIClient(), _token(other))
    assert r.status_code == 401 and r.data["code"] == "invalid_google_token"


def test_not_configured_rejects(settings, transactional_db):
    settings.GOOGLE_CLIENT_IDS = ()
    assert _post(APIClient(), "x").status_code == 401


def test_cannot_set_google_sub_via_profile(api, user):
    api.patch("/api/v1/me", {"google_sub": "victim"}, format="json")
    user.refresh_from_db()
    assert user.google_sub is None
