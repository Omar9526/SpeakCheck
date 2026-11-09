"""Проверка загруженного аудио: сигнатура WAV, формат PCM 16 кГц mono 16 бит, длительность."""
import io
import wave
from dataclasses import dataclass

from django.conf import settings

SAMPLE_RATE = 16_000


class AudioError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass
class AudioInfo:
    duration_ms: int
    peak: int


def validate_wav(data: bytes) -> AudioInfo:
    if len(data) > settings.MAX_AUDIO_BYTES:
        raise AudioError("audio_too_long", f"Запись длиннее {settings.MAX_AUDIO_SECONDS} секунд.")
    if len(data) < 44 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise AudioError("invalid_audio", "Ожидается WAV-файл.")
    try:
        with wave.open(io.BytesIO(data)) as w:
            channels, width, rate, frames = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
            pcm = w.readframes(frames)
    except (wave.Error, EOFError) as exc:
        raise AudioError("invalid_audio", "Повреждённый WAV-файл.") from exc
    if channels != 1 or width != 2 or rate != SAMPLE_RATE:
        raise AudioError("invalid_audio_format", "Нужен WAV PCM 16 кГц, 16 бит, моно.")
    duration_ms = int(frames * 1000 / rate)
    if duration_ms < 500:
        raise AudioError("audio_too_short", "Запись слишком короткая.")
    if duration_ms > settings.MAX_AUDIO_SECONDS * 1000:
        raise AudioError("audio_too_long", f"Запись длиннее {settings.MAX_AUDIO_SECONDS} секунд.")
    peak = _peak(pcm)
    if peak < 300:  # ~ -40 dBFS
        raise AudioError("audio_too_quiet", "Запись слишком тихая — говорите громче или ближе к микрофону.")
    return AudioInfo(duration_ms=duration_ms, peak=peak)


def _peak(pcm: bytes) -> int:
    import array

    samples = array.array("h")
    samples.frombytes(pcm[: len(pcm) - len(pcm) % 2])
    return max((abs(s) for s in samples), default=0)
