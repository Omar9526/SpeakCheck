import logging

from django.db import transaction
from django.utils import timezone

from services import azure_speech, deepseek, storage

from .models import AIExplanation, Assessment, ReadingAttempt, WordAssessment

log = logging.getLogger(__name__)


def run_assessment(attempt_id) -> None:
    """Оценка попытки. Идемпотентно: завершённую попытку не трогаем (повторная доставка задачи)."""
    with transaction.atomic():
        attempt = ReadingAttempt.objects.select_for_update().select_related("user").filter(id=attempt_id).first()
        if attempt is None or attempt.status in (ReadingAttempt.Status.COMPLETED, ReadingAttempt.Status.FAILED):
            return
        attempt.status = ReadingAttempt.Status.PROCESSING
        attempt.save(update_fields=["status", "updated_at"])

    try:
        result = azure_speech.assess(str(storage.path_for(attempt.audio_key)), attempt.reference_text, attempt.duration_ms)
    except azure_speech.AssessmentFailed as exc:
        _fail(attempt, exc.code)
        return
    except Exception:  # noqa: BLE001 — неизвестная ошибка провайдера
        log.exception("assessment crashed attempt=%s", attempt.id)
        _fail(attempt, "provider_error")
        return

    with transaction.atomic():
        assessment = Assessment.objects.create(
            attempt=attempt,
            overall=result.overall, accuracy=result.accuracy, fluency=result.fluency,
            completeness=result.completeness, prosody=result.prosody,
            assessed_word_count=result.assessed_word_count,
            raw_provider_json=result.raw,
        )
        WordAssessment.objects.bulk_create([
            WordAssessment(assessment=assessment, index=w["index"], word=w["word"][:128], start_ms=w["start_ms"],
                           end_ms=w["end_ms"], score=w["score"], error_type=w["error_type"], phonemes_json=w["phonemes"])
            for w in result.words
        ])
        attempt.status = ReadingAttempt.Status.COMPLETED
        attempt.score_version = result.score_version
        attempt.save(update_fields=["status", "score_version", "updated_at"])
    _cleanup_audio(attempt)


def _fail(attempt, code):
    attempt.status = ReadingAttempt.Status.FAILED
    attempt.failure_code = code
    attempt.save(update_fields=["status", "failure_code", "updated_at"])
    _cleanup_audio(attempt)


def _cleanup_audio(attempt):
    """По умолчанию аудио удаляется сразу после анализа; хранится только по выбору пользователя (ТЗ 11)."""
    if attempt.user.preferences.get("keep_audio"):
        return
    storage.delete(attempt.audio_key)
    ReadingAttempt.objects.filter(id=attempt.id).update(audio_key=None)


def get_or_create_explanation(assessment: Assessment, language: str) -> AIExplanation:
    existing = AIExplanation.objects.filter(assessment=assessment).first()
    if existing and existing.language == language and not existing.is_fallback:
        return existing  # кеш: повторно не платим за вызов
    words = [
        {"word": w.word, "score": w.score, "error_type": w.error_type, "phonemes": w.phonemes_json}
        for w in assessment.words.all()
    ]
    scores = {k: getattr(assessment, k) for k in ("overall", "accuracy", "fluency", "completeness", "prosody")}
    try:
        data = deepseek.explain(assessment.attempt.reference_text, scores, words, language)
        model, is_fallback = deepseek.settings.DEEPSEEK_MODEL, False
    except deepseek.ExplanationError:
        data, model, is_fallback = deepseek.fallback(words), "fallback-template", True
    obj, _ = AIExplanation.objects.update_or_create(
        assessment=assessment,
        defaults={"model": model, "language": language, "summary": data["summary"], "tips_json": data["tips"],
                  "encouragement": data["encouragement"], "is_fallback": is_fallback},
    )
    return obj


def delete_user_data(user) -> None:
    for key in ReadingAttempt.objects.filter(user=user).exclude(audio_key=None).values_list("audio_key", flat=True):
        storage.delete(key)
    storage.delete_user_dir(user.id)
    user.documents.all().delete()
    user.attempts.all().delete()
