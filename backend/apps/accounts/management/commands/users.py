"""Список аккаунтов: python manage.py users [--limit 30] [--all-guests].

Имя и email — из аккаунта Apple/Google (у гостей их нет).
"""
from django.core.management.base import BaseCommand
from django.db.models import Count, Max, Q

from apps.accounts.models import User


def provider(u) -> str:
    if u.google_sub:
        return "Google"
    if u.apple_sub:
        return "Apple"
    return "гость"


class Command(BaseCommand):
    help = "Показать зарегистрированные аккаунты и их активность"

    def add_arguments(self, parser):
        parser.add_argument("--limit", type=int, default=30)
        parser.add_argument("--all-guests", action="store_true",
                            help="показывать и гостей без единой попытки")

    def handle(self, *args, limit, all_guests, **options):
        users = User.objects.all()
        total = users.count()
        google = users.exclude(google_sub=None).count()
        apple = users.exclude(apple_sub=None).count()
        guests = users.filter(is_guest=True).count()
        self.stdout.write(f"Всего аккаунтов: {total}  ·  Google: {google}  ·  Apple: {apple}  ·  гостей: {guests}\n")

        rows = users.annotate(docs=Count("documents", distinct=True), tries=Count("attempts", distinct=True),
                              last=Max("attempts__created_at")).order_by("-created_at")
        if not all_guests:
            rows = rows.filter(Q(is_guest=False) | Q(tries__gt=0))
        self.stdout.write(f"{'ID':<10} {'вход':<7} {'имя':<22} {'email':<30} {'создан':<17} {'попыток':>7}  последняя")
        for u in rows[:limit]:
            last = u.last.strftime("%d.%m.%Y %H:%M") if u.last else "—"
            self.stdout.write(f"{str(u.id)[:8]:<10} {provider(u):<7} {(u.name or '—')[:22]:<22} "
                              f"{(u.email or '—')[:30]:<30} {u.created_at:%d.%m.%Y %H:%M} {u.tries:>7}  {last}")
        if not all_guests:
            self.stdout.write("\n(гости без попыток скрыты — добавьте --all-guests)")
