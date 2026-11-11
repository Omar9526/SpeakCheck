import io
import math
import struct
import wave

import pytest
from rest_framework.test import APIClient

from apps.accounts.models import User


@pytest.fixture(autouse=True)
def _clear_throttle_cache():
    from django.core.cache import cache

    cache.clear()
    yield
    cache.clear()


@pytest.fixture(autouse=True)
def _private_storage(settings, tmp_path):
    settings.PRIVATE_STORAGE_ROOT = tmp_path / "private"
    settings.AZURE_SPEECH_KEY = ""
    settings.DEEPSEEK_API_KEY = ""
    settings.ELEVENLABS_API_KEY = ""
    settings.REST_FRAMEWORK = {**settings.REST_FRAMEWORK, "DEFAULT_THROTTLE_CLASSES": []}


def make_wav(seconds=2.0, amplitude=8000, rate=16000, channels=1, width=2) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(width)
        w.setframerate(rate)
        frames = int(seconds * rate)
        w.writeframes(b"".join(struct.pack("<h", int(amplitude * math.sin(i / 8))) for i in range(frames)) * channels)
    return buf.getvalue()


@pytest.fixture
def wav():
    return make_wav


def client_for(user):
    c = APIClient()
    c.force_authenticate(user)
    return c


@pytest.fixture
def user(transactional_db):
    return User.objects.create_user(is_guest=True)


@pytest.fixture
def other_user(transactional_db):
    return User.objects.create_user(is_guest=True)


@pytest.fixture
def api(user):
    return client_for(user)


@pytest.fixture
def document(api):
    r = api.post("/api/v1/documents", {
        "filename": "Lesson.txt", "source": "txt",
        "segments": [{"reference_text": "Hello world."}, {"reference_text": "Learning English is fun."}],
    }, format="json")
    assert r.status_code == 201, r.data
    return r.data
