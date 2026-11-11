"""Бесконечная тренировка: следующий текст под уровень и слабые звуки пользователя.

Тексты пишет DeepSeek и проверяет сервер (только английский, нужная длина, без мусора).
Готовые тексты переиспользуются между пользователями; если DeepSeek недоступен — запасной набор.
"""
from __future__ import annotations

import json
import logging
import random
import re

import requests
from django.conf import settings
from django.db import IntegrityError

from apps.reading.models import Assessment, PracticeServed, PracticeText, WordAssessment

log = logging.getLogger(__name__)

LEVELS = ["A2", "B1", "B2", "C1"]
# Фрагмент ≤ 40 слов: Azure размечает пропуски только для записей до 30 секунд.
LENGTH = {"A2": (16, 24), "B1": (22, 30), "B2": (26, 34), "C1": (30, 40)}
LEVEL_DESC = {
    "A2": "elementary: short simple sentences, very common words",
    "B1": "intermediate: everyday vocabulary, some linking words",
    "B2": "upper-intermediate: varied vocabulary, complex sentences",
    "C1": "advanced: natural idioms, longer sentences, precise vocabulary",
}
TOPICS = {
    "ielts": ["your hometown", "your work or studies", "a hobby you enjoy", "a memorable trip", "technology in daily life",
              "the environment", "food you like", "a person you admire", "a memorable day", "a book you read",
              "music", "sport and health", "shopping habits", "the weather where you live", "learning languages"],
    "interview": ["tell me about yourself", "your main strengths", "a weakness you are working on", "teamwork",
                  "resolving a conflict", "your biggest achievement", "why you want this job", "salary expectations",
                  "working remotely", "leading a project", "learning from a failure", "your five-year goals"],
    "life": ["ordering at a cafe", "checking in at the airport", "a visit to the doctor", "booking a hotel room",
             "a phone call to make an appointment", "small talk with a neighbour", "asking for directions",
             "renting an apartment", "opening a bank account", "a polite complaint in a restaurant"],
    "surprise": ["an amazing fact about space", "a short funny story", "a surprising fact about animals",
                 "a small piece of history", "a motivational thought", "a strange invention", "a famous city"],
}
TOPIC_NAMES = {"ielts": "IELTS", "interview": "Собеседование", "life": "Жизнь", "surprise": "Сюрприз"}
# Подсказка для UI: звук и пример слова.
SOUND_HINTS = {
    "θ": "think", "ð": "this", "r": "red", "ɹ": "red", "w": "we", "v": "very", "æ": "cat", "ɪ": "sit",
    "i": "see", "ŋ": "sing", "h": "hat", "ʒ": "vision", "dʒ": "job", "tʃ": "chair", "ɝ": "bird",
    "ɚ": "teacher", "ʊ": "book", "u": "food", "ɔ": "law", "ɑ": "hot", "ʌ": "cup", "eɪ": "day", "oʊ": "go",
    "aɪ": "my", "aʊ": "now", "ɔɪ": "boy", "ʃ": "she", "z": "zoo", "l": "light", "p": "pen", "t": "ten", "d": "dog",
}
ALLOWED = re.compile(r"^[A-Za-z0-9 ,.'!?;:\-\"()]+$")


class GenerationError(Exception):
    pass


# ---------- уровень и слабые звуки ----------

def current_level(user) -> str:
    """Уровень растёт при среднем ≥ 88 за 3 последние попытки и снижается при < 60 (не чаще раза в 3 попытки)."""
    prefs = user.preferences or {}
    scores = list(Assessment.objects.filter(attempt__user=user, overall__isnull=False)
                  .order_by("-created_at").values_list("overall", flat=True)[:3])
    total = Assessment.objects.filter(attempt__user=user).count()
    level = prefs.get("practice_level")
    if level not in LEVELS:
        avg = sum(scores) / len(scores) if scores else None
        level = "A2" if avg is None or avg < 70 else ("B1" if avg < 85 else "B2")
    elif len(scores) == 3 and total - prefs.get("practice_level_at", 0) >= 3:
        avg = sum(scores) / 3
        i = LEVELS.index(level)
        if avg >= 88 and i < len(LEVELS) - 1:
            level = LEVELS[i + 1]
        elif avg < 60 and i > 0:
            level = LEVELS[i - 1]
    if level != prefs.get("practice_level"):
        user.preferences = {**prefs, "practice_level": level, "practice_level_at": total}
        user.save(update_fields=["preferences"])
    return level


def weak_sounds(user, limit: int = 3) -> list[str]:
    """Звуки с худшей средней оценкой за последние 15 попыток (минимум 3 появления, среднее < 75)."""
    recent = Assessment.objects.filter(attempt__user=user).order_by("-created_at").values_list("id", flat=True)[:15]
    stats: dict[str, list[float]] = {}
    for phonemes in WordAssessment.objects.filter(assessment_id__in=list(recent)).values_list("phonemes_json", flat=True):
        for p in phonemes or []:
            ph, score = p.get("phoneme"), p.get("score")
            if ph in SOUND_HINTS and isinstance(score, (int, float)):
                stats.setdefault(ph, []).append(float(score))
    ranked = sorted(((sum(v) / len(v), ph) for ph, v in stats.items() if len(v) >= 3 and sum(v) / len(v) < 75))
    return [ph for _, ph in ranked[:limit]]


# ---------- выдача следующего текста ----------

def next_text(user, topic: str) -> tuple[PracticeText, str]:
    level = current_level(user)
    weak = weak_sounds(user)
    topic = topic if topic in TOPICS else "surprise"
    unseen = PracticeText.objects.exclude(served__user=user)

    # Сначала — любой готовый непрочитанный текст этого уровня и темы: на слабый звук (чаще)
    # или без фокуса. Новый текст пишем, только если готовых нет — иначе человек ждёт DeepSeek.
    ready = unseen.filter(level=level, topic=topic, focus__in=weak + [""])
    text = (ready.exclude(focus="").order_by("?").first() if weak and random.random() < 0.75 else None) \
        or ready.order_by("?").first()
    if text is None:
        focus = random.choice(weak) if weak and random.random() < 0.75 else ""
        try:
            text = _generate(level, topic, focus)
        except GenerationError as exc:
            log.warning("practice generation failed: %s", exc)
            text = (unseen.filter(level=level, topic=topic).order_by("?").first()
                    or unseen.filter(level=level).order_by("?").first()
                    or _bank(level, user))
    try:
        PracticeServed.objects.create(user=user, text=text)
    except IntegrityError:
        pass  # запасной текст мог повториться — не страшно
    return text, level


def prefill(user_id, topic: str) -> None:
    """Если для пользователя нет непрочитанного текста под его уровень и тему — пишем один заранее."""
    from apps.accounts.models import User

    user = User.objects.filter(id=user_id).first()
    if user is None or topic not in TOPICS or not settings.DEEPSEEK_API_KEY:
        return
    level = current_level(user)
    weak = weak_sounds(user)
    unseen = PracticeText.objects.exclude(served__user=user).filter(level=level, topic=topic)
    if unseen.filter(focus__in=weak + [""]).count() >= 2:
        return  # запас уже есть
    focus = random.choice(weak) if weak and not unseen.filter(focus__in=weak).exists() else ""
    try:
        _generate(level, topic, focus)
    except GenerationError as exc:
        log.info("practice prefill skipped: %s", exc)


def _generate(level: str, topic: str, focus: str) -> PracticeText:
    if not settings.DEEPSEEK_API_KEY:
        raise GenerationError("not_configured")
    lo, hi = LENGTH[level]
    subject = random.choice(TOPICS[topic])
    focus_line = (f"Naturally use many words with the sound /{focus}/ (as in \"{SOUND_HINTS[focus]}\"). "
                  if focus else "")
    prompt = (
        f"Write a text for reading aloud. Level {level} — {LEVEL_DESC[level]}. "
        f"Subject: {subject}. Length: {lo}-{hi} words, 2-3 sentences, first person, sounds like real speech. "
        f"{focus_line}No real people's names, no lists, no line breaks, no emoji. "
        'Reply in json: {"title": "2-5 word English title", "text": "the text"}'
    )
    body = {
        "model": settings.DEEPSEEK_MODEL,
        "messages": [
            {"role": "system", "content": "You write short English practice texts for Russian-speaking learners "
                                          "who read them aloud to train pronunciation. Reply only with json."},
            {"role": "user", "content": prompt},
        ],
        "response_format": {"type": "json_object"},
        "max_tokens": 1000,  # с запасом: при малом лимите DeepSeek иногда возвращает пустой ответ
        "temperature": 1.0,
    }
    headers = {"Authorization": f"Bearer {settings.DEEPSEEK_API_KEY}", "Content-Type": "application/json"}
    url = settings.DEEPSEEK_BASE_URL.rstrip("/") + "/chat/completions"
    last = "unknown"
    for _ in range(3):
        try:
            resp = requests.post(url, json=body, headers=headers, timeout=settings.DEEPSEEK_TIMEOUT)
            if resp.status_code != 200:
                raise GenerationError(f"http_{resp.status_code}")
            content = resp.json()["choices"][0]["message"]["content"] or ""
            if not content.strip():
                raise GenerationError("empty")  # документированный случай JSON-режима — повторяем
            data = json.loads(content)
            title, text = validate(data, level)
            return PracticeText.objects.create(level=level, topic=topic, focus=focus, title=title, text=text)
        except (requests.RequestException, ValueError, KeyError, IndexError, TypeError, GenerationError) as exc:
            last = str(exc) if isinstance(exc, GenerationError) else type(exc).__name__
    raise GenerationError(last)


def _clean(value) -> str:
    if not isinstance(value, str):
        raise GenerationError("not_string")
    value = (value.replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"')
             .replace("—", "-").replace("–", "-"))
    return re.sub(r"\s+", " ", value).strip()


def validate(data: dict, level: str) -> tuple[str, str]:
    """Только английские буквы и обычная пунктуация, длина под уровень, без ссылок."""
    title, text = _clean(data.get("title")), _clean(data.get("text"))
    lo, hi = LENGTH[level]
    words = len(text.split())
    if not (lo - 6 <= words <= hi + 6) or words > 45:
        raise GenerationError(f"length_{words}")
    if not ALLOWED.match(text) or not ALLOWED.match(title or "x"):
        raise GenerationError("characters")
    if "http" in text.lower() or "www" in text.lower():
        raise GenerationError("link")
    title = title[:60] or "Practice"
    return title, text


# ---------- запасной набор (если DeepSeek недоступен) ----------

BANK = {
    "A2": [("My Morning", "I wake up at seven and drink a cup of tea. Then I walk to work with my friend. We talk about our plans for the day."),
           ("Weekend Plans", "This weekend I want to visit my parents. We will cook dinner together and watch a good film. I think it will be fun."),
           ("My Room", "My room is small but very bright. There is a big window, a desk and many books. I like to read there in the evening.")],
    "B1": [("Learning English", "I started learning English three years ago because I wanted to travel more. Now I can watch films without subtitles, and I feel much more confident."),
           ("A Busy Day", "Yesterday was really busy at work. We had three meetings, and I finished an important report just before the deadline. In the evening I finally relaxed."),
           ("My City", "My city is surrounded by mountains, so the air is fresh in the morning. In summer people go hiking, and in winter the slopes are full of skiers.")],
    "B2": [("Remote Work", "Working remotely has completely changed my routine. Although I miss chatting with colleagues, I appreciate the flexibility and the extra time I no longer spend commuting."),
           ("Teamwork", "In my previous role, I coordinated a team of five people. We disagreed at first, but after we clarified our goals, we delivered the project ahead of schedule."),
           ("Technology", "Smartphones have made our lives easier, yet they also make it harder to focus. I try to switch off notifications whenever I need to concentrate on something important.")],
    "C1": [("A Career Turn", "Switching careers was a daunting decision, but it turned out to be the most rewarding thing I have done. It taught me that discomfort is often a sign of genuine growth."),
           ("Cities and Nature", "As cities continue to expand, preserving green spaces becomes increasingly vital. Thoughtful urban planning can balance economic development with the wellbeing of the people who live there."),
           ("Leadership", "Effective leadership is less about giving orders and more about creating an environment where people feel trusted. When teams feel valued, they consistently exceed expectations.")],
}


def _bank(level: str, user) -> PracticeText:
    items = BANK[level]
    seen = set(PracticeServed.objects.filter(user=user, text__source="bank").values_list("text__text", flat=True))
    title, text = next(((t, x) for t, x in items if x not in seen), random.choice(items))
    obj = PracticeText.objects.filter(source="bank", text=text).first()
    return obj or PracticeText.objects.create(level=level, topic="surprise", title=title, text=text, source="bank")
