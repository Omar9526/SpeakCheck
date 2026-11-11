"""Azure AI Speech — Pronunciation Assessment (scripted reading).

Сверено с документацией Microsoft (how-to-pronunciation-assessment, обновление 2025-11):
- до 30 с аудио: recognize_once + EnableMiscue → движок сам размечает Omission/Insertion;
- длиннее 30 с: continuous mode, EnableMiscue НЕ поддерживается → пропуски не показываем,
  CompletenessScore считаем недоступным (ТЗ 6: не придумывать метрики);
- ProsodyScore только для en-US (enable_prosody_assessment);
- Offset/Duration — в единицах 100 нс; фонемы запрашиваем в IPA.
"""
from __future__ import annotations

import json
import logging
import threading
from dataclasses import dataclass, field

from django.conf import settings

log = logging.getLogger(__name__)

SCORE_VERSION_SHORT = "azure-pa-v1-scripted"
SCORE_VERSION_CONTINUOUS = "azure-pa-v1-continuous"
SHORT_MODE_MAX_MS = 30_000
MIN_COMPLETENESS = 25.0  # ниже — речь не соответствует тексту
# Azure ставит «Monotone» сразу всем словам фразы, даже при хорошей интонации.
# Показываем пометку, только если интонация фразы действительно слабая.
MONOTONE_PROSODY_MAX = 70.0

ERROR_TYPES = {"None", "Omission", "Insertion", "Mispronunciation", "UnexpectedBreak", "MissingBreak", "Monotone"}


class AssessmentFailed(Exception):
    """Оценка невозможна. code уходит клиенту (ТЗ 4.3)."""

    def __init__(self, code: str, retryable: bool = False):
        super().__init__(code)
        self.code = code
        self.retryable = retryable


@dataclass
class NormalizedAssessment:
    overall: float | None
    accuracy: float | None
    fluency: float | None
    completeness: float | None
    prosody: float | None
    words: list[dict] = field(default_factory=list)
    score_version: str = SCORE_VERSION_SHORT
    raw: dict | list = field(default_factory=dict)

    @property
    def assessed_word_count(self) -> int:
        return sum(1 for w in self.words if w["score"] is not None and w["error_type"] != "Insertion")


def is_configured() -> bool:
    return bool(settings.AZURE_SPEECH_KEY and settings.AZURE_SPEECH_REGION)


def assess(wav_path: str, reference_text: str, duration_ms: int) -> NormalizedAssessment:
    if not is_configured():
        raise AssessmentFailed("service_not_configured", retryable=True)
    import azure.cognitiveservices.speech as speechsdk

    speech_config = speechsdk.SpeechConfig(subscription=settings.AZURE_SPEECH_KEY, region=settings.AZURE_SPEECH_REGION)
    # Меньше дробления на фразы при паузах чтения.
    speech_config.set_property(speechsdk.PropertyId.Speech_SegmentationSilenceTimeoutMs, "1500")
    audio_config = speechsdk.audio.AudioConfig(filename=wav_path)
    short = duration_ms <= SHORT_MODE_MAX_MS

    pa_config = speechsdk.PronunciationAssessmentConfig(json_string=json.dumps({
        "referenceText": reference_text,
        "gradingSystem": "HundredMark",
        "granularity": "Phoneme",
        "phonemeAlphabet": "IPA",
        "enableMiscue": short,
    }))
    prosody = settings.AZURE_LOCALE == "en-US"
    if prosody:
        pa_config.enable_prosody_assessment()

    recognizer = speechsdk.SpeechRecognizer(speech_config=speech_config, language=settings.AZURE_LOCALE,
                                            audio_config=audio_config)
    pa_config.apply_to(recognizer)

    if short:
        result = recognizer.recognize_once()
        payloads = [_payload(result, speechsdk)]
        return normalize_short(payloads[0], reference_text)

    payloads = _recognize_continuous(recognizer, speechsdk)
    return normalize_continuous(payloads)


def _payload(result, speechsdk) -> dict:
    reason = result.reason
    if reason == speechsdk.ResultReason.RecognizedSpeech:
        return json.loads(result.properties.get(speechsdk.PropertyId.SpeechServiceResponse_JsonResult))
    if reason == speechsdk.ResultReason.NoMatch:
        raise AssessmentFailed("no_speech")
    if reason == speechsdk.ResultReason.Canceled:
        details = result.cancellation_details
        log.warning("azure canceled: reason=%s code=%s", details.reason, getattr(details, "error_code", None))
        raise AssessmentFailed("provider_unavailable", retryable=True)
    raise AssessmentFailed("provider_error", retryable=True)


def _recognize_continuous(recognizer, speechsdk) -> list[dict]:
    done = threading.Event()
    payloads: list[dict] = []
    errors: list[str] = []

    def on_recognized(evt):
        if evt.result.reason == speechsdk.ResultReason.RecognizedSpeech:
            payloads.append(json.loads(evt.result.properties.get(speechsdk.PropertyId.SpeechServiceResponse_JsonResult)))

    def on_canceled(evt):
        if evt.cancellation_details.reason == speechsdk.CancellationReason.Error:
            errors.append(str(getattr(evt.cancellation_details, "error_code", "error")))
        done.set()

    recognizer.recognized.connect(on_recognized)
    recognizer.session_stopped.connect(lambda evt: done.set())
    recognizer.canceled.connect(on_canceled)
    recognizer.start_continuous_recognition()
    finished = done.wait(timeout=settings.MAX_AUDIO_SECONDS * 2 + 30)
    recognizer.stop_continuous_recognition()
    if errors or not finished:
        raise AssessmentFailed("provider_unavailable", retryable=True)
    if not payloads:
        raise AssessmentFailed("no_speech")
    return payloads


# ---------- нормализация (чистые функции, покрыты тестами) ----------

def _pa(obj) -> dict:
    return (obj or {}).get("PronunciationAssessment") or {}


def _round(v):
    return None if v is None else round(float(v), 1)


def _ticks_to_ms(v):
    return None if v is None else int(v) // 10_000


def _word(index: int, w: dict, allow_miscue: bool) -> dict | None:
    pa = _pa(w)
    error_type = pa.get("ErrorType", "None")
    if error_type not in ERROR_TYPES:
        error_type = "None"
    if not allow_miscue and error_type in {"Omission", "Insertion"}:
        return None  # в continuous mode такие метки ненадёжны — не показываем
    # Monotone из Feedback.Prosody.Intonation
    intonation = ((pa.get("Feedback") or {}).get("Prosody") or {}).get("Intonation") or {}
    if error_type == "None" and "Monotone" in (intonation.get("ErrorTypes") or []):
        error_type = "Monotone"
    omitted = error_type == "Omission"
    phonemes = [
        {"phoneme": p.get("Phoneme", ""), "score": _round(_pa(p).get("AccuracyScore"))}
        for p in (w.get("Phonemes") or []) if p.get("Phoneme")
    ] or None
    return {
        "index": index,
        "word": w.get("Word", ""),
        "start_ms": None if omitted else _ticks_to_ms(w.get("Offset")),
        "end_ms": None if omitted else (
            _ticks_to_ms(w.get("Offset")) + _ticks_to_ms(w.get("Duration"))
            if w.get("Offset") is not None and w.get("Duration") is not None else None),
        "score": None if omitted else _round(pa.get("AccuracyScore")),
        "error_type": error_type,
        "phonemes": None if omitted else phonemes,
    }


def normalize_short(payload: dict, reference_text: str = "") -> NormalizedAssessment:
    best = (payload.get("NBest") or [None])[0]
    if not best:
        raise AssessmentFailed("no_speech")
    pa = _pa(best)
    words = [w for i, raw in enumerate(best.get("Words") or []) if (w := _word(i, raw, allow_miscue=True))]
    if not words:
        raise AssessmentFailed("no_speech")
    completeness = _round(pa.get("CompletenessScore"))
    if completeness is not None and completeness < MIN_COMPLETENESS:
        raise AssessmentFailed("text_mismatch")
    result = NormalizedAssessment(
        overall=_round(pa.get("PronScore")),
        accuracy=_round(pa.get("AccuracyScore")),
        fluency=_round(pa.get("FluencyScore")),
        completeness=completeness,
        prosody=_round(pa.get("ProsodyScore")),
        words=words,
        score_version=SCORE_VERSION_SHORT,
        raw=payload,
    )
    if result.assessed_word_count == 0:
        raise AssessmentFailed("low_confidence")
    _filter_monotone(result.words, result.prosody)
    return result


def _filter_monotone(words: list[dict], prosody: float | None) -> None:
    if prosody is not None and prosody < MONOTONE_PROSODY_MAX:
        return
    for w in words:
        if w["error_type"] == "Monotone":
            w["error_type"] = "None"


def normalize_continuous(payloads: list[dict]) -> NormalizedAssessment:
    """Несколько фраз: метрики фраз взвешиваются по числу оценённых слов (как сводка ТЗ 6).
    Completeness недоступна (miscue не поддерживается в continuous mode)."""
    parts = []
    words: list[dict] = []
    for payload in payloads:
        best = (payload.get("NBest") or [None])[0]
        if not best:
            continue
        part_words = [w for raw in (best.get("Words") or []) if (w := _word(len(words), raw, allow_miscue=False))]
        for w in part_words:
            w["index"] = len(words)
            words.append(w)
        n = sum(1 for w in part_words if w["score"] is not None)
        parts.append((_pa(best), n))
    if not words:
        raise AssessmentFailed("no_speech")

    def weighted(key):
        num = den = 0.0
        for pa, n in parts:
            v = pa.get(key)
            if v is None or n <= 0:
                continue
            num += float(v) * n
            den += n
        return round(num / den, 1) if den else None

    prosody = weighted("ProsodyScore")
    _filter_monotone(words, prosody)
    return NormalizedAssessment(
        overall=weighted("PronScore"),
        accuracy=weighted("AccuracyScore"),
        fluency=weighted("FluencyScore"),
        completeness=None,
        prosody=prosody,
        words=words,
        score_version=SCORE_VERSION_CONTINUOUS,
        raw=payloads,
    )
