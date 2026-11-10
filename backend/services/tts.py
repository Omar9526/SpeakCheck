"""Эталонное произношение живым нейросетевым голосом Azure (Text to Speech, REST).

Готовый MP3 кэшируется на диске по хэшу (голос + скорость + текст): повторное «Послушать»
и одинаковые готовые тексты у разных людей не оплачиваются второй раз.
Файлы лежат в приватном хранилище и не раздаются по HTTP напрямую.
"""
from __future__ import annotations

import hashlib
import logging
import os
from pathlib import Path
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


def is_configured() -> bool:
    return bool(settings.AZURE_SPEECH_KEY and settings.AZURE_SPEECH_REGION)


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


def synthesize(text: str, slow: bool = False) -> bytes:
    voice = settings.AZURE_TTS_VOICE
    path = _cache_path(text, voice, slow)
    if path.exists():
        return path.read_bytes()
    if not is_configured():
        raise SynthesisFailed("service_not_configured")

    url = f"https://{settings.AZURE_SPEECH_REGION}.tts.speech.microsoft.com/cognitiveservices/v1"
    try:
        r = requests.post(url, data=build_ssml(text, voice, slow).encode(), timeout=15, headers={
            "Ocp-Apim-Subscription-Key": settings.AZURE_SPEECH_KEY,
            "Content-Type": "application/ssml+xml",
            "X-Microsoft-OutputFormat": OUTPUT_FORMAT,
            "User-Agent": "SpeakCheck",
        })
    except requests.RequestException as e:
        log.warning("azure tts network error: %s", type(e).__name__)
        raise SynthesisFailed("provider_unavailable") from e
    if r.status_code != 200 or not r.content:
        log.warning("azure tts status=%s", r.status_code)
        raise SynthesisFailed("provider_unavailable")

    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(r.content)
    os.chmod(tmp, 0o600)
    tmp.replace(path)  # атомарно: параллельный запрос не прочитает недописанный файл
    return r.content
