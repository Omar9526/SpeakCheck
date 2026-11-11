"""Бесконечная тренировка: выдача текстов, переиспользование, запасной набор, уровни, проверка текста."""
import json
from unittest import mock

import pytest

from apps.reading.models import Assessment, Document, PracticeServed, PracticeText, ReadingAttempt, WordAssessment
from services import practice

GOOD = {"title": "Three Things", "text": "I think three things matter most when I travel: a good map, "
        "a warm smile and enough patience for long queues at the station."}


class Resp:
    def __init__(self, content, status=200):
        self.status_code = status
        self._content = content

    def json(self):
        return {"choices": [{"message": {"content": self._content}}]}


@pytest.fixture(autouse=True)
def no_prefill(request):
    """Фоновая подготовка следующего текста проверяется отдельным тестом."""
    if "prefill" in request.node.name:
        yield
        return
    with mock.patch("apps.reading.tasks.prefill_practice.delay"):
        yield


@pytest.fixture
def deepseek(settings):
    settings.DEEPSEEK_API_KEY = "k"
    with mock.patch("services.practice.requests.post", return_value=Resp(json.dumps(GOOD))) as post:
        yield post


def _next(api, topic="ielts"):
    return api.post("/api/v1/practice/next", {"topic": topic}, format="json")


def test_generates_text_and_marks_served(api, user, deepseek):
    r = _next(api)
    assert r.status_code == 200
    assert r.data["text"] == GOOD["text"] and r.data["level"] == "A2" and r.data["topic_name"] == "IELTS"
    assert PracticeServed.objects.filter(user=user).count() == 1


def test_pool_reused_for_other_user_without_calling_deepseek(api, user, other_user, deepseek):
    from tests.conftest import client_for

    with mock.patch("services.practice.random.random", return_value=0.99):  # без фокуса на звук
        _next(api)
        r = _next(client_for(other_user))
    assert r.data["text"] == GOOD["text"]
    assert deepseek.call_count == 1  # второй пользователь получил готовый текст бесплатно


def test_same_user_never_gets_same_text_twice(api, deepseek):
    first = _next(api).data["id"]
    second = _next(api).data["id"]
    assert first != second and deepseek.call_count == 2


def test_falls_back_to_bank_when_deepseek_down(api, settings):
    settings.DEEPSEEK_API_KEY = "k"
    with mock.patch("services.practice.requests.post", return_value=Resp("", status=402)):
        texts = {_next(api).data["text"] for _ in range(3)}
    assert len(texts) == 3  # три разных запасных текста подряд
    assert all(t in {x for _, x in practice.BANK["A2"]} for t in texts)


def test_works_without_deepseek_key(api):
    r = _next(api)
    assert r.status_code == 200 and r.data["text"]


def test_bad_generated_text_rejected(api, settings):
    settings.DEEPSEEK_API_KEY = "k"
    bad = [{"title": "x", "text": "Привет, это русский текст для проверки фильтра на сервере сегодня утром."},
           {"title": "x", "text": "Visit http example com " * 3},
           {"title": "x", "text": "Too short."},
           {"title": "x", "text": " ".join(["word"] * 60)}]
    for item in bad:
        with mock.patch("services.practice.requests.post", return_value=Resp(json.dumps(item))):
            r = _next(api)
        assert r.data["text"] != item["text"]  # отбраковано → запасной текст
    assert not PracticeText.objects.filter(source="ai").exists()


def test_unknown_topic_rejected(api):
    assert _next(api, "hack").status_code == 400


def test_requires_auth(transactional_db):
    from rest_framework.test import APIClient
    assert APIClient().post("/api/v1/practice/next", {}, format="json").status_code == 401


def _assessment(user, overall, phonemes=None):
    doc = Document.objects.create(user=user, filename="t")
    attempt = ReadingAttempt.objects.create(user=user, document=doc, reference_text="t", status="completed")
    a = Assessment.objects.create(attempt=attempt, overall=overall)
    WordAssessment.objects.create(assessment=a, index=0, word="think", score=overall, phonemes_json=phonemes or [])
    return a


def test_level_goes_up_and_down(user):
    for _ in range(3):
        _assessment(user, 75)
    assert practice.current_level(user) == "B1"
    for _ in range(3):
        _assessment(user, 95)
    assert practice.current_level(user) == "B2"
    for _ in range(3):
        _assessment(user, 40)
    assert practice.current_level(user) == "B1"


def test_level_does_not_jump_every_request(user):
    for _ in range(3):
        _assessment(user, 95)
    first = practice.current_level(user)
    assert practice.current_level(user) == first  # без новых попыток уровень не меняется


def test_weak_sounds_found(user):
    for _ in range(3):
        _assessment(user, 70, [{"phoneme": "θ", "score": 30}, {"phoneme": "s", "score": 95}, {"phoneme": "r", "score": 60}])
    assert practice.weak_sounds(user) == ["θ", "r"]


def test_focus_sound_in_prompt(api, user, deepseek):
    for _ in range(3):
        _assessment(user, 70, [{"phoneme": "θ", "score": 30}])
    with mock.patch("services.practice.random.random", return_value=0.1):
        r = _next(api)
    assert r.data["focus_sound"] == "θ" and r.data["focus_example"] == "think"
    assert "/θ/" in deepseek.call_args.kwargs["json"]["messages"][1]["content"]


def test_next_prefills_following_text(api, user, deepseek):
    with mock.patch("services.practice.random.random", return_value=0.99):
        _next(api)  # выдан один текст, второй пишется заранее (Celery в тестах синхронный)
        assert deepseek.call_count == 2
        assert PracticeText.objects.exclude(served__user=user).filter(topic="ielts").count() == 1
        before = deepseek.call_count
        _next(api)  # следующий берётся из заранее готового, сам запрос DeepSeek не ждёт
    assert PracticeServed.objects.filter(user=user).count() == 2
    assert deepseek.call_count == before + 1  # +1 — это уже подготовка следующего
