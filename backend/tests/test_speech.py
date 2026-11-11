from unittest import mock

import pytest

from services import tts


class FakeResponse:
    def __init__(self, status=200, content=b"ID3mp3"):
        self.status_code = status
        self.content = content


@pytest.fixture
def azure(settings):
    settings.AZURE_SPEECH_KEY = "k"
    settings.AZURE_SPEECH_REGION = "westeurope"
    settings.AZURE_TTS_VOICE = "en-US-AvaMultilingualNeural"


def test_not_configured_returns_503(api):
    r = api.post("/api/v1/speech", {"text": "Hello"}, format="json")
    assert r.status_code == 503
    assert r.json()["code"] == "service_not_configured"


def test_requires_auth(transactional_db):
    from rest_framework.test import APIClient
    r = APIClient().post("/api/v1/speech", {"text": "Hello"}, format="json")
    assert r.status_code == 401


def test_returns_mp3_and_caches(api, azure):
    with mock.patch("services.tts.requests.post", return_value=FakeResponse()) as post:
        r1 = api.post("/api/v1/speech", {"text": "Hello world"}, format="json")
        r2 = api.post("/api/v1/speech", {"text": "Hello world"}, format="json")
    assert r1.status_code == 200 and r1["Content-Type"] == "audio/mpeg"
    assert r1.content == b"ID3mp3" and r2.content == b"ID3mp3"
    assert post.call_count == 1  # второй раз — из кэша, Azure не оплачивается


def test_slow_is_separate_cache_entry(api, azure):
    with mock.patch("services.tts.requests.post", return_value=FakeResponse()) as post:
        api.post("/api/v1/speech", {"text": "Hello"}, format="json")
        api.post("/api/v1/speech", {"text": "Hello", "slow": True}, format="json")
    assert post.call_count == 2
    assert 'rate="-25%"' in post.call_args.kwargs["data"].decode()


def test_ssml_escapes_text():
    ssml = tts.build_ssml('</voice><voice name="x">&', "en-US-AvaMultilingualNeural", False)
    assert "</voice><voice" not in ssml.split(">", 2)[2].rsplit("</voice>", 1)[0]
    assert "&lt;/voice&gt;" in ssml and "&amp;" in ssml


def test_text_limits(api, azure, settings):
    assert api.post("/api/v1/speech", {"text": ""}, format="json").status_code == 400
    long = "a" * (settings.MAX_SEGMENT_CHARS + 1)
    assert api.post("/api/v1/speech", {"text": long}, format="json").status_code == 400


def test_provider_error_not_cached(api, azure):
    with mock.patch("services.tts.requests.post", return_value=FakeResponse(status=429, content=b"")):
        assert api.post("/api/v1/speech", {"text": "Hi"}, format="json").status_code == 503
    with mock.patch("services.tts.requests.post", return_value=FakeResponse()) as post:
        assert api.post("/api/v1/speech", {"text": "Hi"}, format="json").status_code == 200
    assert post.call_count == 1


@pytest.fixture
def eleven(settings):
    settings.ELEVENLABS_API_KEY = "xi"
    settings.ELEVENLABS_VOICE_ID = "voice123"
    settings.ELEVENLABS_MODEL = "eleven_multilingual_v2"


def test_elevenlabs_preferred_over_azure(api, azure, eleven):
    with mock.patch("services.tts.requests.post", return_value=FakeResponse()) as post:
        r = api.post("/api/v1/speech", {"text": "Hello", "slow": True}, format="json")
    assert r.status_code == 200
    args, kwargs = post.call_args
    assert args[0] == "https://api.elevenlabs.io/v1/text-to-speech/voice123"
    assert kwargs["headers"]["xi-api-key"] == "xi"
    assert kwargs["json"] == {"text": "Hello", "model_id": "eleven_multilingual_v2", "voice_settings": {"speed": 0.8}}


def test_voice_change_is_new_cache_entry(api, eleven, settings):
    with mock.patch("services.tts.requests.post", return_value=FakeResponse()) as post:
        api.post("/api/v1/speech", {"text": "Hello"}, format="json")
        settings.ELEVENLABS_VOICE_ID = "other"
        api.post("/api/v1/speech", {"text": "Hello"}, format="json")
    assert post.call_count == 2


def test_voice_id_cannot_escape_path(api, eleven, settings):
    settings.ELEVENLABS_VOICE_ID = "../v1/user"
    with mock.patch("services.tts.requests.post", return_value=FakeResponse()) as post:
        api.post("/api/v1/speech", {"text": "Hello"}, format="json")
    assert post.call_args.args[0].endswith("/text-to-speech/..%2Fv1%2Fuser")
