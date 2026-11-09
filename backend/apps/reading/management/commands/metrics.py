"""Метрики для условий совета директоров (founder/board.md) — только из своих данных, без сторонней аналитики.

    python manage.py metrics            # за последние 30 дней
    python manage.py metrics --days 7
"""
from collections import Counter
from datetime import timedelta
from statistics import median

from django.core.management.base import BaseCommand
from django.db.models import Count, Q, Sum
from django.utils import timezone

from apps.accounts.models import User
from apps.reading.models import AIExplanation, Challenge, Document, ReadingAttempt


def pct(part, whole):
    return f"{100 * part / whole:.0f}%" if whole else "—"


def p90(values):
    if not values:
        return None
    values = sorted(values)
    return values[min(len(values) - 1, int(len(values) * 0.9))]


def collect(days: int) -> dict:
    since = timezone.now() - timedelta(days=days)
    users = User.objects.filter(created_at__gte=since)
    completed = ReadingAttempt.objects.filter(status=ReadingAttempt.Status.COMPLETED)

    # Активация: первая оценка и время до неё (присылает приложение).
    activated = users.filter(attempts__status=ReadingAttempt.Status.COMPLETED).distinct()
    first_score = [u.preferences["first_score_seconds"] for u in users if "first_score_seconds" in u.preferences]

    # Возвраты: занимался на следующий день / через 7 дней после первой оценки.
    d1 = d7 = eligible_d1 = eligible_d7 = 0
    now = timezone.now()
    for user in activated:
        days_active = sorted({d for d in completed.filter(user=user).values_list("created_at__date", flat=True)})
        first = days_active[0]
        if (now.date() - first).days >= 1:
            eligible_d1 += 1
            d1 += any((d - first).days == 1 for d in days_active)
        if (now.date() - first).days >= 7:
            eligible_d7 += 1
            d7 += any((d - first).days >= 7 for d in days_active)

    # Скорость и надёжность оценки.
    recent = ReadingAttempt.objects.filter(created_at__gte=since)
    round_trip = [(a.updated_at - a.created_at).total_seconds()
                  for a in recent.filter(status=ReadingAttempt.Status.COMPLETED).only("created_at", "updated_at")]
    failures = Counter(recent.filter(status=ReadingAttempt.Status.FAILED).values_list("failure_code", flat=True))

    # Вирусная петля «Вызов другу».
    challenges = Challenge.objects.filter(created_at__gte=since)
    accepted = Document.objects.filter(challenge__in=challenges, attempts__status=ReadingAttempt.Status.COMPLETED)
    new_from_challenge = users.filter(documents__challenge__isnull=False).distinct().count()

    # Нагрузка для расчёта себестоимости (/founder-cfo).
    audio_ms = recent.aggregate(s=Sum("duration_ms"))["s"] or 0
    explanations = AIExplanation.objects.filter(created_at__gte=since).aggregate(
        ai=Count("id", filter=Q(is_fallback=False)), fallback=Count("id", filter=Q(is_fallback=True)))

    return {
        "days": days,
        "users": users.count(),
        "goals": Counter(u.preferences.get("goal", "не указана") for u in users),
        "activated": activated.count(),
        "first_score": first_score,
        "d1": (d1, eligible_d1), "d7": (d7, eligible_d7),
        "attempts": recent.count(),
        "round_trip": round_trip,
        "failures": failures,
        "challenges": challenges.count(),
        "challenge_owners": challenges.values("owner").distinct().count(),
        "challenge_opens": challenges.aggregate(s=Sum("opened_count"))["s"] or 0,
        "challenge_accepted": accepted.values("challenge").distinct().count(),
        "new_from_challenge": new_from_challenge,
        "audio_minutes": audio_ms / 60000,
        "explanations": explanations,
    }


class Command(BaseCommand):
    help = "Метрики продукта по условиям совета директоров"

    def add_arguments(self, parser):
        parser.add_argument("--days", type=int, default=30)

    def handle(self, *args, days, **options):
        m = collect(days)
        out = self.stdout.write
        out(f"SpeakCheck — метрики за {m['days']} дн.\n")
        out("Активация")
        out(f"  новых пользователей: {m['users']}  (цели: {dict(m['goals'])})")
        out(f"  получили первую оценку: {m['activated']} ({pct(m['activated'], m['users'])})")
        fs = m["first_score"]
        if fs:
            fast = sum(1 for s in fs if s <= 60)
            out(f"  время до первой оценки: медиана {median(fs):.0f} с, ≤60 с у {pct(fast, len(fs))} (цель совета: 60 с)")
        out(f"  вернулись на следующий день: {m['d1'][0]} из {m['d1'][1]} ({pct(*m['d1'])})")
        out(f"  занимались через 7+ дней: {m['d7'][0]} из {m['d7'][1]} ({pct(*m['d7'])})")
        out("\nОценка")
        out(f"  попыток: {m['attempts']}")
        if m["round_trip"]:
            out(f"  время ответа: медиана {median(m['round_trip']):.1f} с, p90 {p90(m['round_trip']):.1f} с")
        if m["failures"]:
            out(f"  сбои: {dict(m['failures'])}")
        out("\n«Вызов другу»")
        out(f"  создано вызовов: {m['challenges']} (авторов: {m['challenge_owners']}, "
            f"{pct(m['challenge_owners'], m['activated'])} активных)")
        out(f"  открытий ссылок: {m['challenge_opens']}, принято (друг получил оценку): {m['challenge_accepted']}")
        out(f"  новых пользователей пришло через вызов: {m['new_from_challenge']}")
        out("\nНагрузка (для /founder-cfo)")
        out(f"  минут аудио в Azure: {m['audio_minutes']:.1f}")
        e = m["explanations"]
        out(f"  объяснений DeepSeek: {e['ai']} (шаблонных без ИИ: {e['fallback']})")
