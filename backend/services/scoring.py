"""Сводка по фрагментам: взвешивание по числу оценённых слов (ТЗ, раздел 6)."""

METRICS = ("overall", "accuracy", "fluency", "completeness", "prosody")


def weighted_summary(assessments) -> dict:
    """assessments: объекты/словари с метриками и assessed_word_count. Отсутствующие метрики не усредняются."""
    result = {}
    total_words = 0
    for a in assessments:
        total_words += _get(a, "assessed_word_count") or 0
    for metric in METRICS:
        num, den = 0.0, 0
        for a in assessments:
            value, weight = _get(a, metric), _get(a, "assessed_word_count") or 0
            if value is None or weight <= 0:
                continue
            num += value * weight
            den += weight
        result[metric] = round(num / den, 1) if den else None
    result["word_count"] = total_words
    return result


def _get(obj, key):
    return obj.get(key) if isinstance(obj, dict) else getattr(obj, key, None)
