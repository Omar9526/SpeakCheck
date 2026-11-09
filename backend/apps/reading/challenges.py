import html
import secrets

from django.conf import settings
from django.http import HttpResponse, HttpResponseNotFound
from django.db.models import F
from rest_framework import permissions, serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

from core.errors import APIError

from .models import Challenge, ReadingAttempt

ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"


def new_code() -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(8))


class ChallengeSerializer(serializers.ModelSerializer):
    url = serializers.SerializerMethodField()

    class Meta:
        model = Challenge
        fields = ["code", "title", "reference_text", "owner_score", "url", "created_at"]

    def get_url(self, obj):
        return f"{settings.PUBLIC_BASE_URL.rstrip('/')}/c/{obj.code}"


class ChallengeCreateView(APIView):
    """POST /challenges {attempt_id} — вызов создаётся только из реальной завершённой попытки (без выдуманных баллов)."""

    def post(self, request):
        attempt = ReadingAttempt.objects.filter(
            id=request.data.get("attempt_id"), user=request.user, status=ReadingAttempt.Status.COMPLETED
        ).select_related("assessment", "document").first()
        if attempt is None:
            raise APIError("not_found", "Попытка не найдена.", 404)
        existing = Challenge.objects.filter(owner=request.user, reference_text=attempt.reference_text,
                                            owner_score=attempt.assessment.overall).first()
        challenge = existing or Challenge.objects.create(
            code=new_code(), owner=request.user, title=attempt.document.filename[:120],
            reference_text=attempt.reference_text, owner_score=attempt.assessment.overall,
        )
        return Response(ChallengeSerializer(challenge).data, status=status.HTTP_201_CREATED)


class ChallengeDetailView(APIView):
    """GET /challenges/{code} — текст вызова для приложения друга."""

    def get(self, request, code):
        challenge = Challenge.objects.filter(code=code).first()
        if challenge is None:
            raise APIError("not_found", "Вызов не найден.", 404)
        Challenge.objects.filter(pk=challenge.pk).update(opened_count=F("opened_count") + 1)
        return Response(ChallengeSerializer(challenge).data)


def challenge_landing(request, code):
    """Публичная страница по ссылке из мессенджера: открыть в приложении или скачать."""
    challenge = Challenge.objects.filter(code=code).first()
    if challenge is None:
        return HttpResponseNotFound("Вызов не найден")
    score = f"{round(challenge.owner_score)}%" if challenge.owner_score is not None else "—"
    preview = html.escape(challenge.reference_text[:220])
    app_link = f"speakcheck://c/{code}"
    store = html.escape(settings.APP_STORE_URL)
    page = f"""<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Вызов SpeakCheck: {score}</title>
<meta property="og:title" content="Друг прочитал текст на английском на {score}. Сможешь лучше?">
<meta property="og:description" content="Прочитай тот же текст вслух в SpeakCheck и сравни произношение.">
<style>
body{{margin:0;font-family:-apple-system,system-ui,sans-serif;background:#101C32;color:#F8FAFC;display:flex;min-height:100vh;align-items:center;justify-content:center}}
.c{{max-width:420px;margin:16px;padding:28px;background:#1E293B;border-radius:20px}}
.s{{font-size:64px;font-weight:800;background:linear-gradient(90deg,#2563EB,#38BDF8);-webkit-background-clip:text;color:transparent}}
p{{color:#94A3B8;line-height:1.5}} q{{display:block;color:#F8FAFC;font-size:17px;margin:16px 0}}
a{{display:block;text-align:center;padding:16px;border-radius:16px;font-weight:700;text-decoration:none;margin-top:12px}}
.p{{background:linear-gradient(90deg,#2563EB,#38BDF8);color:#fff}} .g{{background:#263449;color:#F8FAFC}}
</style></head><body><div class="c">
<div>🎙️ SpeakCheck</div><div class="s">{score}</div>
<p>Твой друг прочитал этот текст на английском. Сможешь произнести лучше?</p>
<q>{preview}</q>
<a class="p" href="{app_link}">Принять вызов</a>
<a class="g" href="{store}">Скачать SpeakCheck</a>
</div></body></html>"""
    return HttpResponse(page)
