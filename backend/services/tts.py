"""Эталонное произношение живым голосом: ElevenLabs (если задан ключ), иначе Azure Text to Speech.

Готовый MP3 кэшируется на диске по хэшу (голос + скорость + текст): повторное «Послушать»
и одинаковые готовые тексты у разных людей не оплачиваются второй раз.
Файлы лежат в приватном хранилище и не раздаются по HTTP напрямую.
"""
from __future__ import annotations

import hashlib
import logging
import os
from pathlib import Path
from urllib.parse import quote
from xml.sax.saxutils import escape, quoteattr

import requests
from django.conf import settings

log = logging.getLogger(__name__)

OUTPUT_FORMAT = "audio-24khz-48kbitrate-mono-mp3"
SLOW_RATE = "-25%"


class SynthesisFailed(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def provider() -> str | None:
    if settings.ELEVENLABS_API_KEY:
        return "elevenlabs"
    if settings.AZURE_SPEECH_KEY and settings.AZURE_SPEECH_REGION:
        return "azure"
    return None


def is_configured() -> bool:
    return provider() is not None


def build_ssml(text: str, voice: str, slow: bool) -> str:
    body = escape(text)
    if slow:
        body = f"<prosody rate={quoteattr(SLOW_RATE)}>{body}</prosody>"
    return (f'<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-US">'
            f"<voice name={quoteattr(voice)}>{body}</voice></speak>")


def _cache_path(text: str, voice: str, slow: bool) -> Path:
    digest = hashlib.sha256(f"{voice}|{int(slow)}|{text}".encode()).hexdigest()
    folder = Path(settings.PRIVATE_STORAGE_ROOT) / "tts" / digest[:2]
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    return folder / f"{digest}.mp3"


def synthesize(text: str, slow: bool = False, voice: str = "") -> bytes:
    voice = voice if voice in settings.ELEVENLABS_VOICES else settings.DEFAULT_TTS_VOICE
    name = provider()
    voice_key = (f"elevenlabs:{settings.ELEVENLABS_VOICES[voice]}:{settings.ELEVENLABS_MODEL}" if name == "elevenlabs"
                 else f"azure:{settings.AZURE_TTS_VOICES[voice]}")
    path = _cache_path(text, voice_key, slow)
    if path.exists():
        return path.read_bytes()
    if name is None:
        raise SynthesisFailed("service_not_configured")

    try:
        r = (_request_elevenlabs(text, slow, voice) if name == "elevenlabs"
             else _request_azure(text, slow, voice))
    except requests.RequestException as e:
        log.warning("%s tts network error: %s", name, type(e).__name__)
        raise SynthesisFailed("provider_unavailable") from e
    if r.status_code != 200 or not r.content:
        log.warning("%s tts status=%s", name, r.status_code)
        raise SynthesisFailed("provider_unavailable")

    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(r.content)
    os.chmod(tmp, 0o600)
    tmp.replace(path)  # атомарно: параллельный запрос не прочитает недописанный файл
    return r.content


def _request_azure(text: str, slow: bool, voice: str) -> requests.Response:
    url = f"https://{settings.AZURE_SPEECH_REGION}.tts.speech.microsoft.com/cognitiveservices/v1"
    return requests.post(url, data=build_ssml(text, settings.AZURE_TTS_VOICES[voice], slow).encode(), timeout=15, headers={
        "Ocp-Apim-Subscription-Key": settings.AZURE_SPEECH_KEY,
        "Content-Type": "application/ssml+xml",
        "X-Microsoft-OutputFormat": OUTPUT_FORMAT,
        "User-Agent": "SpeakCheck",
    })


def _request_elevenlabs(text: str, slow: bool, voice: str) -> requests.Response:
    voice_id = quote(settings.ELEVENLABS_VOICES[voice], safe="")
    return requests.post(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}",
        params={"output_format": "mp3_44100_64"},
        json={"text": text, "model_id": settings.ELEVENLABS_MODEL,
              "voice_settings": {"speed": 0.8 if slow else 1.0}},
        headers={"xi-api-key": settings.ELEVENLABS_API_KEY, "Accept": "audio/mpeg"},
        timeout=20,
    )
