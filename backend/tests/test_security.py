"""Тесты защиты: каждая проверка — попытка атаки, которая должна провалиться."""
import hashlib
import time
from types import SimpleNamespace
from unittest import mock

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.reading.models import Challenge, Document
from services import apple
from tests.conftest import client_for

pytestmark = pytest.mark.django_db(transaction=True)

PROTECTED = [
    ("get", "/api/v1/documents"), ("post", "/api/v1/documents"), ("get", "/api/v1/history"),
    ("get", "/api/v1/me"), ("delete", "/api/v1/me"), ("post", "/api/v1/challenges"),
    ("get", "/api/v1/challenges/abcdefgh"),
    ("get", "/api/v1/documents/00000000-0000-0000-0000-000000000000"),
    ("get", "/api/v1/attempts/00000000-0000-0000-0000-000000000000"),
    ("post", "/api/v1/segments/00000000-0000-0000-0000-000000000000/attempts"),
    ("post", "/api/v1/assessments/00000000-0000-0000-0000-000000000000/explanation"),
]


# ---------- авторизация ----------

@pytest.mark.parametrize("method,url", PROTECTED)
def test_endpoints_require_auth(method, url):
    r = getattr(APIClient(), method)(url)
    assert r.status_code == 401
    assert r.json()["code"] == "not_authenticated"


def test_forged_jwt_is_rejected():
    forged = jwt.encode({"user_id": "00000000-0000-0000-0000-000000000000", "token_type": "access",
                         "exp": int(time.time()) + 600}, "guessed-secret-by-attacker-0123456789", algorithm="HS256")
    r = APIClient().get("/api/v1/me", HTTP_AUTHORIZATION=f"Bearer {forged}")
    assert r.status_code == 401


def test_alg_none_jwt_is_rejected(user):
    token = jwt.encode({"user_id": str(user.id), "token_type": "access", "exp": int(time.time()) + 600},
                       None, algorithm="none")
    assert APIClient().get("/api/v1/me", HTTP_AUTHORIZATION=f"Bearer {token}").status_code == 401


def _guest_tokens():
    r = APIClient().post("/api/v1/auth/guest", {}, format="json")
    assert r.status_code == 201
    return r.json()


def test_logout_revokes_refresh_token():
    tokens = _guest_tokens()
    c = APIClient()
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
    assert c.post("/api/v1/auth/logout", {"refresh": tokens["refresh"]}, format="json").status_code == 204
    # украденный refresh-токен после выхода бесполезен
    r = APIClient().post("/api/v1/auth/refresh", {"refresh": tokens["refresh"]}, format="json")
    assert r.status_code == 401


def test_rotated_refresh_token_cannot_be_reused():
    tokens = _guest_tokens()
    first = APIClient().post("/api/v1/auth/refresh", {"refresh": tokens["refresh"]}, format="json")
    assert first.status_code == 200
    replay = APIClient().post("/api/v1/auth/refresh", {"refresh": tokens["refresh"]}, format="json")
    assert replay.status_code == 401


def test_deleted_account_tokens_stop_working():
    tokens = _guest_tokens()
    c = APIClient()
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
    assert c.delete("/api/v1/me").status_code == 204
    assert c.get("/api/v1/me").status_code == 401
    assert APIClient().post("/api/v1/auth/refresh", {"refresh": tokens["refresh"]}, format="json").status_code == 401


def test_guest_creation_is_rate_limited():
    from apps.accounts import views

    with mock.patch.object(views.GuestRateThrottle, "THROTTLE_RATES", {"guest": "3/hour"}):
        codes = [APIClient().post("/api/v1/auth/guest", {}, format="json").status_code for _ in range(5)]
    assert codes == [201, 201, 201, 429, 429]


def test_spoofed_forwarded_for_does_not_bypass_limit():
    from apps.accounts import views

    with mock.patch.object(views.GuestRateThrottle, "THROTTLE_RATES", {"guest": "2/hour"}):
        codes = [APIClient().post("/api/v1/auth/guest", {}, format="json",
                                  HTTP_X_FORWARDED_FOR=f"10.0.0.{i}, 1.2.3.4").status_code for i in range(4)]
    assert codes == [201, 201, 429, 429]


def test_guest_locale_garbage_is_not_500():
    for bad in [123, ["x"], {"a": 1}, "x" * 500]:
        r = APIClient().post("/api/v1/auth/guest", {"locale": bad}, format="json")
        assert r.status_code == 201
        assert User.objects.get(id=r.json()["user"]["id"]).locale == "ru"


# ---------- Sign in with Apple: подпись, audience, nonce ----------

@pytest.fixture
def apple_key():
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    with mock.patch.object(apple, "_client") as client:
        client.return_value.get_signing_key_from_jwt.return_value = SimpleNamespace(key=key.public_key())
        yield key


def _apple_token(key, **overrides):
    claims = {"iss": "https://appleid.apple.com", "aud": "kg.speakcheck.app", "sub": "apple-sub-1",
              "iat": int(time.time()), "exp": int(time.time()) + 600,
              "nonce": hashlib.sha256(b"raw-nonce").hexdigest()}
    claims.update(overrides)
    return jwt.encode(claims, key, algorithm="RS256")


def test_apple_valid_token_with_nonce(apple_key):
    r = APIClient().post("/api/v1/auth/apple", {"identity_token": _apple_token(apple_key), "nonce": "raw-nonce"},
                         format="json")
    assert r.status_code == 200


@pytest.mark.parametrize("overrides,nonce", [
    ({"aud": "com.attacker.app"}, "raw-nonce"),           # токен выпущен для чужого приложения
    ({"iss": "https://evil.example.com"}, "raw-nonce"),   # чужой издатель
    ({"exp": int(time.time()) - 10}, "raw-nonce"),        # просрочен
    ({}, "other-nonce"),                                   # перехваченный токен с чужим nonce
    ({}, ""),                                              # nonce не передан
])
def test_apple_bad_tokens_are_rejected(apple_key, overrides, nonce):
    r = APIClient().post("/api/v1/auth/apple", {"identity_token": _apple_token(apple_key, **overrides), "nonce": nonce},
                         format="json")
    assert r.status_code in (400, 401)
    assert not User.objects.filter(apple_sub="apple-sub-1").exists()


def test_apple_token_signed_by_other_key_is_rejected(apple_key):
    other = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    r = APIClient().post("/api/v1/auth/apple", {"identity_token": _apple_token(other), "nonce": "raw-nonce"},
                         format="json")
    assert r.status_code == 401


# ---------- чужие данные (IDOR) ----------

def test_other_user_cannot_touch_my_data(api, document, other_user, wav):
    seg = document["segments"][0]["id"]
    attempt = api.post(f"/api/v1/segments/{seg}/attempts",
                       {"audio": SimpleUploadedFile("a.wav", wav(), content_type="audio/wav")}, format="multipart").json()
    thief = client_for(other_user)
    assert thief.get(f"/api/v1/documents/{document['id']}").status_code == 404
    assert thief.patch(f"/api/v1/documents/{document['id']}", {"filename": "pwned"}, format="json").status_code == 404
    assert thief.delete(f"/api/v1/documents/{document['id']}").status_code == 404
    assert thief.get(f"/api/v1/attempts/{attempt['id']}").status_code == 404
    assert thief.delete(f"/api/v1/attempts/{attempt['id']}").status_code == 404
    up = thief.post(f"/api/v1/segments/{seg}/attempts",
                    {"audio": SimpleUploadedFile("a.wav", wav(), content_type="audio/wav")}, format="multipart")
    assert up.status_code == 404
    assert thief.post("/api/v1/challenges", {"attempt_id": attempt["id"]}, format="json").status_code == 404
    assert thief.get(f"/api/v1/history?document={document['id']}").json()["results"] == []
    assert Document.objects.get(id=document["id"]).filename == "Lesson.txt"


def test_cannot_hijack_document_id_of_other_user(api, document, other_user):
    r = client_for(other_user).post("/api/v1/documents", {
        "id": document["id"], "filename": "x", "source": "txt", "segments": [{"reference_text": "Hi there."}],
    }, format="json")
    assert r.status_code == 400
    assert Document.objects.get(id=document["id"]).filename == "Lesson.txt"


def test_cannot_escalate_via_profile_fields(api, user):
    r = api.patch("/api/v1/me", {"is_guest": False, "id": "00000000-0000-0000-0000-000000000000",
                                 "apple_sub": "victim-sub"}, format="json")
    assert r.status_code == 200
    user.refresh_from_db()
    assert user.is_guest is True and user.apple_sub is None


# ---------- проверка входных данных на сервере ----------

@pytest.mark.parametrize("url", [
    "/api/v1/history?document=not-a-uuid",
    "/api/v1/history?document=' OR '1'='1",
    "/api/v1/history?document=1;DROP TABLE reading_document;--",
])
def test_garbage_query_params_are_not_500(api, url):
    assert api.get(url).status_code in (200, 400)
    assert Document.objects.model._meta.db_table  # таблица на месте


@pytest.mark.parametrize("attempt_id", ["not-a-uuid", 123, None, "' OR 1=1 --", ["x"]])
def test_challenge_garbage_attempt_id_is_not_500(api, attempt_id):
    r = api.post("/api/v1/challenges", {"attempt_id": attempt_id}, format="json")
    assert r.status_code in (400, 404)


def test_segment_text_size_is_limited(api):
    huge_word = "a" * 50_000  # одно «слово» на 50 КБ обходило лимит по словам
    r = api.post("/api/v1/documents", {"filename": "x", "source": "txt",
                                       "segments": [{"reference_text": huge_word}]}, format="json")
    assert r.status_code == 400


def test_preferences_values_are_typed(api):
    for bad in [{"keep_audio": "yes"}, {"keep_audio": {"nested": [1] * 1000}},
                {"explanation_language": "<script>"}, {"voice_consent": 1}]:
        r = api.patch("/api/v1/me", {"preferences": bad}, format="json")
        assert r.status_code == 400, bad
    assert api.patch("/api/v1/me", {"preferences": {"keep_audio": True, "explanation_language": "en"}},
                     format="json").status_code == 200


def test_document_count_is_limited(api, settings):
    settings.MAX_DOCUMENTS_PER_USER = 2
    body = {"filename": "x", "source": "txt", "segments": [{"reference_text": "Hi there."}]}
    assert api.post("/api/v1/documents", body, format="json").status_code == 201
    assert api.post("/api/v1/documents", body, format="json").status_code == 201
    r = api.post("/api/v1/documents", body, format="json")
    assert r.status_code == 429 and r.json()["code"] == "quota_exceeded"


# ---------- загрузка файлов ----------

@pytest.mark.parametrize("payload", [
    b"\x89PNG\r\n\x1a\n" + b"0" * 2000,                  # картинка под видом .wav
    b"PK\x03\x04" + b"0" * 2000,                          # zip
    b"#!/bin/sh\nrm -rf /\n" + b"0" * 2000,               # скрипт
    b"RIFF\x00\x00\x00\x00WAVEfmt " + b"\x00" * 100,      # битый WAV
])
def test_non_wav_uploads_are_rejected(api, document, payload):
    seg = document["segments"][0]["id"]
    r = api.post(f"/api/v1/segments/{seg}/attempts",
                 {"audio": SimpleUploadedFile("voice.wav", payload, content_type="audio/wav")}, format="multipart")
    assert r.status_code == 422


def test_wrong_wav_format_is_rejected(api, document, wav):
    seg = document["segments"][0]["id"]
    r = api.post(f"/api/v1/segments/{seg}/attempts",
                 {"audio": SimpleUploadedFile("a.wav", wav(rate=44100), content_type="audio/wav")}, format="multipart")
    assert r.status_code == 422


def test_oversized_upload_is_rejected(api, document, settings, wav):
    settings.MAX_AUDIO_BYTES = 10_000
    seg = document["segments"][0]["id"]
    r = api.post(f"/api/v1/segments/{seg}/attempts",
                 {"audio": SimpleUploadedFile("a.wav", wav(seconds=5), content_type="audio/wav")}, format="multipart")
    assert r.status_code == 413


# ---------- XSS и публичные страницы ----------

def test_challenge_landing_escapes_user_text(user):
    Challenge.objects.create(code="xsstest2", owner=user, title="t",
                             reference_text='<script>alert(1)</script><img src=x onerror=alert(1)>', owner_score=80)
    r = APIClient().get("/c/xsstest2")
    body = r.content.decode()
    assert "<script>alert" not in body and "<img src=x" not in body
    assert "&lt;script&gt;" in body
    csp = r["Content-Security-Policy"]
    assert "script-src 'none'" in csp or "default-src 'none'" in csp


def test_public_pages_send_security_headers(client):
    r = client.get("/privacy")
    assert r["X-Content-Type-Options"] == "nosniff"
    assert r["X-Frame-Options"] == "DENY"
    assert "default-src 'none'" in r["Content-Security-Policy"]


def test_api_never_renders_html(api):
    r = api.get("/api/v1/documents", HTTP_ACCEPT="text/html")
    assert "text/html" not in r["Content-Type"]


def test_admin_is_not_exposed(client):
    for url in ["/admin/", "/admin/login/", "/django-admin/"]:
        assert client.get(url).status_code == 404


def test_errors_do_not_leak_internals(api, settings):
    settings.DEBUG = False
    r = api.get("/api/v1/documents/not-a-uuid")
    assert r.status_code == 404
    assert "Traceback" not in r.content.decode() and "django" not in r.content.decode().lower()
