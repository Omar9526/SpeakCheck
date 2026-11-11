from datetime import timedelta
from io import StringIO
from unittest import mock

import pytest
from django.core.management import call_command
from django.utils import timezone

from apps.reading.management.commands.metrics import collect
from apps.reading.models import Challenge, Document, ReadingAttempt
from services import azure_speech
from tests import azure_samples
from tests.conftest import client_for
from tests.test_api import fake_assess, upload

pytestmark = pytest.mark.django_db(transaction=True)


def test_goal_and_first_score_preferences(api, user):
    r = api.patch("/api/v1/me", {"preferences": {"goal": "ielts", "first_score_seconds": 42}}, format="json")
    assert r.status_code == 200
    for bad in [{"goal": "astronaut"}, {"first_score_seconds": -1}, {"first_score_seconds": "42"},
                {"first_score_seconds": True}]:
        assert api.patch("/api/v1/me", {"preferences": bad}, format="json").status_code == 400


def test_document_links_to_challenge(api, user, other_user):
    ch = Challenge.objects.create(code="abcd2345", owner=other_user, title="t", reference_text="Hello world.",
                                  owner_score=80)
    body = {"filename": "Вызов", "source": "manual", "challenge_code": "abcd2345",
            "segments": [{"reference_text": "Hello world."}]}
    r = api.post("/api/v1/documents", body, format="json")
    assert r.status_code == 201
    assert Document.objects.get(id=r.data["id"]).challenge == ch
    # неизвестный код не ломает создание документа
    r2 = api.post("/api/v1/documents", {**body, "challenge_code": "zzzzzzzz"}, format="json")
    assert r2.status_code == 201 and Document.objects.get(id=r2.data["id"]).challenge is None


def test_metrics_funnel(api, user, other_user, document, wav, settings):
    settings.AZURE_SPEECH_KEY, settings.AZURE_SPEECH_REGION = "k", "r"
    api.patch("/api/v1/me", {"preferences": {"goal": "interview", "first_score_seconds": 35}}, format="json")
    seg = document["segments"][0]["id"]
    with mock.patch("services.azure_speech.assess", side_effect=fake_assess):
        attempt = upload(api, seg, wav()).data
        # друг принимает вызов и тоже получает оценку
        code = api.post("/api/v1/challenges", {"attempt_id": attempt["id"]}, format="json").data["code"]
        friend = client_for(other_user)
        doc = friend.post("/api/v1/documents", {"filename": "Вызов", "source": "manual", "challenge_code": code,
                                                "segments": [{"reference_text": "Hello world."}]}, format="json").data
        upload(friend, doc["segments"][0]["id"], wav())
    # вчерашняя попытка → пользователь вернулся на следующий день
    ReadingAttempt.objects.filter(user=user).update(created_at=timezone.now() - timedelta(days=1))
    with mock.patch("services.azure_speech.assess", side_effect=fake_assess):
        upload(api, seg, wav(), key="second")

    m = collect(30)
    assert m["users"] == 2 and m["activated"] == 2
    assert m["goals"]["interview"] == 1 and m["first_score"] == [35]
    assert m["d1"] == (1, 1)
    assert m["challenges"] == 1 and m["challenge_accepted"] == 1 and m["new_from_challenge"] == 1
    assert m["audio_minutes"] > 0

    out = StringIO()
    call_command("metrics", stdout=out)
    assert "Вызов другу" in out.getvalue()


def test_preferences_patch_merges(api, user):
    api.patch("/api/v1/me", {"preferences": {"first_score_seconds": 30}}, format="json")
    r = api.patch("/api/v1/me", {"preferences": {"keep_audio": True}}, format="json")
    assert r.data["preferences"] == {"first_score_seconds": 30, "keep_audio": True}


def test_users_command_lists_accounts(transactional_db):
    from io import StringIO

    from django.core.management import call_command

    from apps.accounts.models import User

    User.objects.create_user(google_sub="g1")
    User.objects.create_user(apple_sub="a1")
    User.objects.create_user(is_guest=True)
    out = StringIO()
    call_command("users", stdout=out)
    text = out.getvalue()
    assert "Всего аккаунтов: 3" in text and "Google: 1" in text and "Apple: 1" in text
    assert text.count("Google ") >= 1 and "гость " not in text.split("\n", 2)[2]  # гость без попыток скрыт
