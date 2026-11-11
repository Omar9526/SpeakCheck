"""DeepSeek — короткое объяснение ошибок на русском по структурированным результатам Azure.

DeepSeek получает только текст фрагмента и JSON оценок (без аудио) и НЕ меняет числа (ТЗ 8).
Ответ — строго JSON {summary, tips[{word,issue,explanation,exercise}], encouragement};
схема проверяется, при любой проблеме — шаблонный fallback.
API: POST {DEEPSEEK_BASE_URL}/chat/completions, response_format=json_object (docs api-docs.deepseek.com).
"""
from __future__ import annotations

import json
import logging

import requests
from django.conf import settings

log = logging.getLogger(__name__)

MAX_TIPS = 5
MAX_FIELD = 400
FAIR_THRESHOLD = 65.0

SYSTEM_PROMPT = """Ты — доброжелательный преподаватель английского произношения.
Тебе дают эталонный английский текст и результаты автоматической оценки произношения (Azure) в JSON.
Объясни на {language} 1–5 главных ошибок и предложи конкретные короткие упражнения.
Правила:
- Используй ТОЛЬКО ошибки из входных данных; не придумывай новые слова и проценты.
- Не меняй и не пересчитывай числовые оценки, не называй уровень CEFR.
- Объясняй просто: ударение по слогам (com-MU-ni-cate), какие звуки (например /θ/, /r/) и как их произнести.
- Пропущенные слова (Omission) объясняй как пропуск при чтении.
Ответь строго в формате json по схеме:
{{"summary": "1–2 предложения", "tips": [{{"word": "слово", "issue": "кратко, 2–4 слова", "explanation": "1–2 предложения", "exercise": "1 предложение"}}], "encouragement": "1 короткое предложение"}}"""


class ExplanationError(Exception):
    pass


def problem_words(words: list[dict], limit: int = 8) -> list[dict]:
    """Самые проблемные слова для промпта: пропуски и низкие оценки, без лишних данных."""
    bad = [
        w for w in words
        if w.get("error_type") in {"Omission", "Mispronunciation", "Insertion"}
        or (w.get("score") is not None and w["score"] < FAIR_THRESHOLD)
    ]
    bad.sort(key=lambda w: (w.get("score") is not None, w.get("score") or 0))
    out = []
    for w in bad[:limit]:
        item = {"word": w["word"], "error_type": w.get("error_type"), "score": w.get("score")}
        weak = [p for p in (w.get("phonemes") or []) if p.get("score") is not None and p["score"] < FAIR_THRESHOLD]
        if weak:
            item["weak_phonemes"] = [p["phoneme"] for p in weak[:4]]
        out.append(item)
    return out


def build_user_payload(reference_text: str, scores: dict, words: list[dict]) -> str:
    return json.dumps({
        "reference_text": reference_text[:1500],
        "scores": {k: scores.get(k) for k in ("overall", "accuracy", "fluency", "completeness", "prosody")},
        "problem_words": problem_words(words),
    }, ensure_ascii=False)


def validate(data) -> dict:
    if not isinstance(data, dict):
        raise ExplanationError("not_object")
    summary, tips, enc = data.get("summary"), data.get("tips"), data.get("encouragement", "")
    if not isinstance(summary, str) or not summary.strip() or not isinstance(tips, list):
        raise ExplanationError("schema")
    clean = []
    for tip in tips[:MAX_TIPS]:
        if not isinstance(tip, dict):
            continue
        fields = {k: tip.get(k) for k in ("word", "issue", "explanation", "exercise")}
        if not all(isinstance(v, str) for v in fields.values()) or not fields["word"].strip():
            continue
        clean.append({k: v.strip()[:MAX_FIELD] for k, v in fields.items()})
    return {
        "summary": summary.strip()[:MAX_FIELD],
        "tips": clean,
        "encouragement": enc.strip()[:MAX_FIELD] if isinstance(enc, str) else "",
    }


def explain(reference_text: str, scores: dict, words: list[dict], language: str = "ru") -> dict:
    if not settings.DEEPSEEK_API_KEY:
        raise ExplanationError("not_configured")
    lang = "русском языке" if language == "ru" else "English"
    body = {
        "model": settings.DEEPSEEK_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT.format(language=lang)},
            {"role": "user", "content": build_user_payload(reference_text, scores, words)},
        ],
        "response_format": {"type": "json_object"},
        "max_tokens": 900,
        "temperature": 0.3,
    }
    headers = {"Authorization": f"Bearer {settings.DEEPSEEK_API_KEY}", "Content-Type": "application/json"}
    url = settings.DEEPSEEK_BASE_URL.rstrip("/") + "/chat/completions"
    last_error = None
    for _ in range(2):  # пустой content в JSON mode — документированный случай, один повтор
        try:
            resp = requests.post(url, json=body, headers=headers, timeout=settings.DEEPSEEK_TIMEOUT)
            if resp.status_code != 200:
                raise ExplanationError(f"http_{resp.status_code}")
            content = resp.json()["choices"][0]["message"]["content"] or ""
            if not content.strip():
                raise ExplanationError("empty")
            return validate(json.loads(content))
        except (requests.RequestException, ValueError, KeyError, IndexError, ExplanationError) as exc:
            last_error = exc
            log.warning("deepseek failed: %s", type(exc).__name__ if not isinstance(exc, ExplanationError) else exc)
    raise ExplanationError(str(last_error))


def fallback(words: list[dict]) -> dict:
    """Шаблонные подсказки без ИИ — числа не меняются."""
    bad = problem_words(words, limit=3)
    if not bad:
        return {
            "summary": "Все слова прочитаны уверенно — серьёзных ошибок нет.",
            "tips": [],
            "encouragement": "Отлично! Попробуйте текст сложнее или читайте чуть быстрее.",
        }
    tips = []
    for w in bad:
        word = w["word"].strip(".,!?;:\"'()")
        if w.get("error_type") == "Omission":
            tips.append({"word": word, "issue": "пропущено",
                         "explanation": "Слово не было прочитано.",
                         "exercise": f"Перечитайте предложение со словом «{word}» медленно, ведя пальцем по тексту."})
        else:
            sounds = ", ".join(f"/{p}/" for p in w.get("weak_phonemes", []))
            tips.append({"word": word, "issue": "неточное произношение",
                         "explanation": "Послушайте образец и сравните со своей записью."
                                        + (f" Сложнее всего дались звуки {sounds}." if sounds else ""),
                         "exercise": "Повторите слово 3 раза медленно, затем в предложении."})
    return {"summary": f"Обратите внимание на {len(tips)} {_words_ru(len(tips))}.", "tips": tips,
            "encouragement": "Каждая попытка делает произношение увереннее!"}


def _words_ru(n: int) -> str:
    """1 слово, 2 слова, 5 слов, 11 слов, 21 слово."""
    if n % 10 == 1 and n % 100 != 11:
        return "слово"
    if 2 <= n % 10 <= 4 and not 12 <= n % 100 <= 14:
        return "слова"
    return "слов"
