from unittest import mock

import pytest

from apps.accounts.models import User
from apps.reading.models import Assessment, ReadingAttempt
from services import azure_speech, storage
from tests import azure_samples
from tests.conftest import client_for

# transaction=True: Celery-задача ставится через transaction.on_commit и в eager-режиме выполняется сразу.
pytestmark = pytest.mark.django_db(transaction=True)


def upload(api, segment_id, data, key=None):
    from django.core.files.uploadedfile import SimpleUploadedFile

    headers = {"HTTP_IDEMPOTENCY_KEY": key} if key else {}
    return api.post(f"/api/v1/segments/{segment_id}/attempts",
                    {"audio": SimpleUploadedFile("a.wav", data, content_type="audio/wav")},
                    format="multipart", **headers)


def fake_assess(path, text, duration_ms):
    return azure_speech.normalize_short(azure_samples.short_payload())


# ---------- auth ----------

def test_guest_auth_returns_tokens():
    from rest_framework.test import APIClient

    r = APIClient().post("/api/v1/auth/guest", {}, format="json")
    assert r.status_code == 201
    assert r.data["access"] and r.data["refresh"] and r.data["user"]["is_guest"] is True


def test_apple_auth_creates_user_and_links_guest(api, user, document):
    with mock.patch("services.apple.verify_identity_token", return_value={"sub": "apple-123"}):
        r = api.post("/api/v1/auth/apple", {"identity_token": "x"}, format="json")
    assert r.status_code == 200
    user.refresh_from_db()
    assert user.apple_sub == "apple-123" and user.is_guest is False  # гость стал Apple-аккаунтом, данные на месте


def test_apple_auth_merges_guest_into_existing_account(api, user, document):
    existing = User.objects.create_user(apple_sub="apple-777")
    with mock.patch("services.apple.verify_identity_token", return_value={"sub": "apple-777"}):
        r = api.post("/api/v1/auth/apple", {"identity_token": "x"}, format="json")
    assert r.status_code == 200 and r.data["user"]["id"] == str(existing.id)
    assert existing.documents.count() == 1
    assert not User.objects.filter(id=user.id).exists()


def test_invalid_apple_token_uses_error_contract():
    from rest_framework.test import APIClient

    from services.apple import AppleTokenError

    with mock.patch("services.apple.verify_identity_token", side_effect=AppleTokenError("bad")):
        r = APIClient().post("/api/v1/auth/apple", {"identity_token": "x"}, format="json")
    assert r.status_code == 401
    assert set(r.data) == {"code", "message", "request_id"} and r.data["code"] == "invalid_apple_token"


def test_unauthenticated_request_rejected():
    from rest_framework.test import APIClient

    r = APIClient().get("/api/v1/documents")
    assert r.status_code == 401 and r.data["code"] == "not_authenticated"


def test_me_update_preferences_validated(api):
    assert api.patch("/api/v1/me", {"preferences": {"keep_audio": True}}, format="json").status_code == 200
    r = api.patch("/api/v1/me", {"preferences": {"evil": 1}}, format="json")
    assert r.status_code == 400 and r.data["code"] == "validation_error"


def test_delete_account_removes_everything(api, user, document, wav, settings):
    seg = document["segments"][0]["id"]
    user.preferences = {"keep_audio": True}
    user.save()
    with mock.patch("services.azure_speech.assess", side_effect=fake_assess):
        upload(api, seg, wav())
    assert api.delete("/api/v1/me").status_code == 204
    assert not User.objects.filter(id=user.id).exists()
    assert ReadingAttempt.objects.count() == 0
    assert not (settings.PRIVATE_STORAGE_ROOT / str(user.id)).exists()


# ---------- documents ----------

def test_document_crud_and_segment_edit(api, document):
    doc_id = document["id"]
    segs = document["segments"]
    assert [s["sequence"] for s in segs] == [0, 1]

    r = api.patch(f"/api/v1/documents/{doc_id}", {
        "filename": "Renamed",
        "segments": [{"id": segs[1]["id"], "reference_text": "Learning English is great."},
                     {"reference_text": "New paragraph."}],
    }, format="json")
    assert r.status_code == 200
    assert r.data["filename"] == "Renamed"
    assert [s["reference_text"] for s in r.data["segments"]] == ["Learning English is great.", "New paragraph."]
    assert r.data["segments"][0]["id"] == segs[1]["id"]

    listing = api.get("/api/v1/documents")
    assert listing.data["count"] == 1 and listing.data["results"][0]["segment_count"] == 2
    assert api.delete(f"/api/v1/documents/{doc_id}").status_code == 204
    assert api.get(f"/api/v1/documents/{doc_id}").status_code == 404


def test_client_provided_ids_are_kept(api):
    import uuid

    did, sid = str(uuid.uuid4()), str(uuid.uuid4())
    r = api.post("/api/v1/documents", {"id": did, "filename": "x", "segments": [{"id": sid, "reference_text": "Hi there."}]},
                 format="json")
    assert r.data["id"] == did and r.data["segments"][0]["id"] == sid


def test_document_validation(api, settings):
    assert api.post("/api/v1/documents", {"filename": "x", "segments": []}, format="json").status_code == 400
    long = " ".join(["word"] * (settings.MAX_SEGMENT_WORDS + 1))
    assert api.post("/api/v1/documents", {"filename": "x", "segments": [{"reference_text": long}]},
                    format="json").status_code == 400


def test_other_users_cannot_access_resources(document, other_user, wav, api):
    stranger = client_for(other_user)
    doc_id, seg = document["id"], document["segments"][0]["id"]
    assert stranger.get(f"/api/v1/documents/{doc_id}").status_code == 404
    assert stranger.patch(f"/api/v1/documents/{doc_id}", {"filename": "hack"}, format="json").status_code == 404
    assert stranger.delete(f"/api/v1/documents/{doc_id}").status_code == 404
    assert upload(stranger, seg, wav()).status_code == 404
    with mock.patch("services.azure_speech.assess", side_effect=fake_assess):
        attempt = upload(api, seg, wav()).data
    assert stranger.get(f"/api/v1/attempts/{attempt['id']}").status_code == 404
    assert stranger.delete(f"/api/v1/attempts/{attempt['id']}").status_code == 404
    aid = attempt["assessment"]["id"]
    assert stranger.post(f"/api/v1/assessments/{aid}/explanation").status_code == 404
    assert stranger.get("/api/v1/history").data["count"] == 0


# ---------- attempts ----------

def test_attempt_completes_with_azure_result_and_deletes_audio(api, document, wav, settings):
    seg = document["segments"][0]["id"]
    with mock.patch("services.azure_speech.assess", side_effect=fake_assess):
        r = upload(api, seg, wav())
    assert r.status_code == 202
    got = api.get(f"/api/v1/attempts/{r.data['id']}").data
    assert got["status"] == "completed"
    a = got["assessment"]
    assert (a["overall"], a["accuracy"], a["fluency"], a["completeness"], a["prosody"]) == (85.3, 82.0, 88.0, 90.0, 79.0)
    words = {w["word"]: w for w in a["words"]}
    assert words["is"]["error_type"] == "Omission" and words["is"]["score"] is None
    assert words["very"]["error_type"] == "Insertion"
    assert words["fun"]["phonemes"][0] == {"phoneme": "f", "score": 30.0}
    assert a["assessed_word_count"] == 3  # без пропуска и вставки
    attempt = ReadingAttempt.objects.get(id=r.data["id"])
    assert attempt.audio_key is None  # аудио удалено после анализа
    assert attempt.score_version == azure_speech.SCORE_VERSION_SHORT
    assert not any((settings.PRIVATE_STORAGE_ROOT).rglob("*.wav"))


def test_keep_audio_preference_keeps_file(api, user, document, wav):
    user.preferences = {"keep_audio": True}
    user.save()
    with mock.patch("services.azure_speech.assess", side_effect=fake_assess):
        r = upload(api, document["segments"][0]["id"], wav())
    key = ReadingAttempt.objects.get(id=r.data["id"]).audio_key
    assert key and storage.path_for(key).exists()


def test_unconfigured_azure_fails_honestly(api, document, wav):
    r = upload(api, document["segments"][0]["id"], wav())
    got = api.get(f"/api/v1/attempts/{r.data['id']}").data
    assert got["status"] == "failed" and got["failure_code"] == "service_not_configured"
    assert got["assessment"] is None  # никаких выдуманных процентов
    assert Assessment.objects.count() == 0


def test_text_mismatch_fails(api, document, wav):
    def mismatch(*a):
        return azure_speech.normalize_short(azure_samples.short_payload(completeness=10))

    with mock.patch("services.azure_speech.assess", side_effect=mismatch):
        r = upload(api, document["segments"][0]["id"], wav())
    got = api.get(f"/api/v1/attempts/{r.data['id']}").data
    assert got["status"] == "failed" and got["failure_code"] == "text_mismatch"


def test_idempotency_key_returns_same_attempt(api, document, wav):
    seg = document["segments"][0]["id"]
    with mock.patch("services.azure_speech.assess", side_effect=fake_assess) as m:
        first = upload(api, seg, wav(), key="abc-123-xyz")
        second = upload(api, seg, wav(), key="abc-123-xyz")
    assert first.status_code == 202 and second.status_code == 200
    assert first.data["id"] == second.data["id"]
    assert m.call_count == 1  # платный вызов Azure — один раз
    assert ReadingAttempt.objects.count() == 1


def test_retry_creates_new_attempt_history_kept(api, document, wav):
    seg = document["segments"][0]["id"]
    with mock.patch("services.azure_speech.assess", side_effect=fake_assess):
        upload(api, seg, wav())
        upload(api, seg, wav())
    assert ReadingAttempt.objects.count() == 2


@pytest.mark.parametrize("data_kwargs,code", [
    ({"amplitude": 50}, "audio_too_quiet"),
    ({"seconds": 0.2}, "audio_too_short"),
    ({"rate": 44100}, "invalid_audio_format"),
    ({"channels": 2}, "invalid_audio_format"),
])
def test_bad_audio_rejected(api, document, wav, data_kwargs, code):
    r = upload(api, document["segments"][0]["id"], wav(**data_kwargs))
    assert r.status_code == 422 and r.data["code"] == code


def test_non_wav_rejected(api, document):
    r = upload(api, document["segments"][0]["id"], b"%PDF-1.4 not audio at all, definitely not RIFF" * 10)
    assert r.status_code == 422 and r.data["code"] == "invalid_audio"


def test_too_long_audio_rejected(api, document, wav, settings):
    settings.MAX_AUDIO_SECONDS = 2
    settings.MAX_AUDIO_BYTES = 10_000_000
    r = upload(api, document["segments"][0]["id"], wav(seconds=3))
    assert r.status_code == 422 and r.data["code"] == "audio_too_long"


def test_daily_quota(api, document, wav, settings):
    settings.DAILY_ATTEMPTS_PER_USER = 1
    seg = document["segments"][0]["id"]
    with mock.patch("services.azure_speech.assess", side_effect=fake_assess):
        assert upload(api, seg, wav()).status_code == 202
        r = upload(api, seg, wav())
    assert r.status_code == 429 and r.data["code"] == "quota_exceeded"


def test_attempt_survives_segment_edit(api, document, wav):
    seg = document["segments"][0]["id"]
    with mock.patch("services.azure_speech.assess", side_effect=fake_assess):
        attempt = upload(api, seg, wav()).data
    api.patch(f"/api/v1/documents/{document['id']}", {"segments": [{"reference_text": "Totally new text."}]}, format="json")
    got = api.get(f"/api/v1/attempts/{attempt['id']}").data
    assert got["status"] == "completed" and got["segment_id"] is None


# ---------- explanation ----------

def _completed(api, document, wav):
    with mock.patch("services.azure_speech.assess", side_effect=fake_assess):
        return upload(api, document["segments"][0]["id"], wav()).data


def test_explanation_fallback_without_key(api, document, wav):
    attempt = _completed(api, document, wav)
    r = api.post(f"/api/v1/assessments/{attempt['assessment']['id']}/explanation")
    assert r.status_code == 200 and r.data["is_fallback"] is True
    assert {t["word"] for t in r.data["tips"]} == {"is", "fun", "very"}
    # оценки не изменились
    assert api.get(f"/api/v1/attempts/{attempt['id']}").data["assessment"]["overall"] == 85.3


def test_explanation_deepseek_is_cached(api, document, wav, settings):
    settings.DEEPSEEK_API_KEY = "test"
    attempt = _completed(api, document, wav)
    payload = {"summary": "Хорошо.", "tips": [{"word": "fun", "issue": "звук /ʌ/", "explanation": "...", "exercise": "..."}],
               "encouragement": "Молодец!"}
    with mock.patch("services.deepseek.explain", return_value=payload) as m:
        url = f"/api/v1/assessments/{attempt['assessment']['id']}/explanation"
        r1, r2 = api.post(url), api.post(url)
    assert r1.data["is_fallback"] is False and r1.data["tips"][0]["word"] == "fun"
    assert r2.data == r1.data and m.call_count == 1


# ---------- history ----------

def test_history_summary_weighted_and_streak(api, document, wav):
    _completed(api, document, wav)
    r = api.get("/api/v1/history")
    assert r.data["count"] == 1
    assert r.data["summary"]["overall"] == 85.3 and r.data["summary"]["word_count"] == 3
    assert r.data["streak_days"] == 1
    assert r.data["results"][0]["overall"] == 85.3


def test_request_id_header(api):
    r = api.get("/api/v1/me", HTTP_X_REQUEST_ID="client-req-0001")
    assert r["X-Request-ID"] == "client-req-0001"


def test_retryable_failure_can_be_resent_with_same_key(api, document, wav):
    seg = document["segments"][0]["id"]
    first = upload(api, seg, wav(), key="retry-key-0001")
    assert api.get(f"/api/v1/attempts/{first.data['id']}").data["failure_code"] == "service_not_configured"
    with mock.patch("services.azure_speech.assess", side_effect=fake_assess):
        second = upload(api, seg, wav(), key="retry-key-0001")
    assert second.status_code == 202 and second.data["id"] != first.data["id"]
    assert api.get(f"/api/v1/attempts/{second.data['id']}").data["status"] == "completed"
    assert ReadingAttempt.objects.count() == 1


# ---------- challenges ----------

def test_challenge_flow(api, document, wav, other_user):
    attempt = _completed(api, document, wav)
    r = api.post("/api/v1/challenges", {"attempt_id": attempt["id"]}, format="json")
    assert r.status_code == 201 and r.data["owner_score"] == 85.3 and "/c/" in r.data["url"]
    code = r.data["code"]
    assert api.post("/api/v1/challenges", {"attempt_id": attempt["id"]}, format="json").data["code"] == code
    friend = client_for(other_user)
    got = friend.get(f"/api/v1/challenges/{code}")
    assert got.status_code == 200 and got.data["reference_text"] == "Hello world."
    from rest_framework.test import APIClient

    page = APIClient().get(f"/c/{code}")
    assert page.status_code == 200 and "85%" in page.content.decode() and f"speakcheck://c/{code}" in page.content.decode()


def test_challenge_requires_own_completed_attempt(api, document, wav, other_user):
    attempt = _completed(api, document, wav)
    r = client_for(other_user).post("/api/v1/challenges", {"attempt_id": attempt["id"]}, format="json")
    assert r.status_code == 404


def test_challenge_landing_escapes_html(api, user):
    from rest_framework.test import APIClient

    from apps.reading.models import Challenge

    Challenge.objects.create(code="xss12345", owner=user, title="t", reference_text="<script>alert(1)</script>", owner_score=50)
    body = APIClient().get("/c/xss12345").content.decode()
    assert "<script>alert" not in body and "&lt;script&gt;" in body
