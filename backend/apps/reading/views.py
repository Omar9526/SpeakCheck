from datetime import timedelta

from django.conf import settings
from django.db import IntegrityError, transaction
from django.db.models import Count
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import generics, status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from core.errors import APIError
from services import audio, scoring, storage

from .models import AIExplanation, Assessment, Document, ReadingAttempt, ReadingSegment
from .serializers import (
    AttemptSerializer,
    AttemptSummarySerializer,
    DocumentListSerializer,
    DocumentSerializer,
    ExplanationSerializer,
)
from .services import get_or_create_explanation
from .tasks import assess_attempt


class DocumentListCreateView(generics.ListCreateAPIView):
    """GET/POST /documents. Текст извлекается на устройстве (PDFKit/Vision) — сервер получает уже текст."""

    def get_queryset(self):
        return Document.objects.filter(user=self.request.user).annotate(segment_count=Count("segments")).order_by("-created_at")

    def get_serializer_class(self):
        return DocumentSerializer if self.request.method == "POST" else DocumentListSerializer

    def create(self, request, *args, **kwargs):
        s = DocumentSerializer(data=request.data, context={"request": request})
        s.is_valid(raise_exception=True)
        doc = s.save()
        return Response(DocumentSerializer(doc).data, status=status.HTTP_201_CREATED)


class DocumentDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = DocumentSerializer
    http_method_names = ["get", "patch", "delete"]

    def get_queryset(self):
        return Document.objects.filter(user=self.request.user).prefetch_related("segments")

    def perform_destroy(self, doc):
        for key in doc.attempts.exclude(audio_key=None).values_list("audio_key", flat=True):
            storage.delete(key)
        doc.delete()


class AttemptCreateView(APIView):
    """POST /segments/{id}/attempts — multipart: audio (WAV 16 кГц mono), заголовок Idempotency-Key."""

    parser_classes = [MultiPartParser, FormParser]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "attempts"

    def post(self, request, segment_id):
        segment = get_object_or_404(
            ReadingSegment.objects.select_related("document"), id=segment_id, document__user=request.user
        )
        key = (request.headers.get("Idempotency-Key") or "")[:64] or None
        if key:
            existing = ReadingAttempt.objects.filter(user=request.user, idempotency_key=key).first()
            if existing:
                return Response(AttemptSerializer(existing).data, status=status.HTTP_200_OK)

        since = timezone.now() - timedelta(days=1)
        if ReadingAttempt.objects.filter(user=request.user, created_at__gte=since).count() >= settings.DAILY_ATTEMPTS_PER_USER:
            raise APIError("quota_exceeded", "Дневной лимит попыток исчерпан. Попробуйте завтра.", 429)

        upload = request.FILES.get("audio")
        if upload is None:
            raise APIError("audio_required", "Не передан файл записи.")
        if upload.size > settings.MAX_AUDIO_BYTES:
            raise APIError("audio_too_long", f"Запись длиннее {settings.MAX_AUDIO_SECONDS} секунд.", 413)
        data = upload.read()
        try:
            info = audio.validate_wav(data)
        except audio.AudioError as exc:
            raise APIError(exc.code, exc.message, 422)

        audio_key = storage.save_audio(request.user.id, data)
        try:
            with transaction.atomic():
                attempt = ReadingAttempt.objects.create(
                    user=request.user, segment=segment, document=segment.document,
                    reference_text=segment.reference_text, audio_key=audio_key,
                    duration_ms=info.duration_ms, idempotency_key=key,
                )
        except IntegrityError:
            storage.delete(audio_key)
            existing = ReadingAttempt.objects.get(user=request.user, idempotency_key=key)
            return Response(AttemptSerializer(existing).data, status=status.HTTP_200_OK)

        transaction.on_commit(lambda: assess_attempt.delay(str(attempt.id)))
        attempt.refresh_from_db()
        return Response(AttemptSerializer(attempt).data, status=status.HTTP_202_ACCEPTED)


class AttemptDetailView(generics.RetrieveDestroyAPIView):
    serializer_class = AttemptSerializer

    def get_queryset(self):
        return ReadingAttempt.objects.filter(user=self.request.user).select_related("assessment").prefetch_related(
            "assessment__words"
        )

    def perform_destroy(self, attempt):
        storage.delete(attempt.audio_key)
        attempt.delete()


class ExplanationView(APIView):
    """POST /assessments/{id}/explanation — объяснение DeepSeek (кешируется, fallback при сбое)."""

    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "explanations"

    def post(self, request, assessment_id):
        assessment = get_object_or_404(
            Assessment.objects.select_related("attempt"), id=assessment_id, attempt__user=request.user
        )
        language = request.data.get("language") or request.user.preferences.get("explanation_language", "ru")
        if language not in ("ru", "en"):
            language = "ru"
        cached = AIExplanation.objects.filter(assessment=assessment, language=language, is_fallback=False).exists()
        if not cached:
            since = timezone.now() - timedelta(days=1)
            used = AIExplanation.objects.filter(assessment__attempt__user=request.user, created_at__gte=since).count()
            if used >= settings.DAILY_EXPLANATIONS_PER_USER:
                raise APIError("quota_exceeded", "Дневной лимит объяснений исчерпан.", 429)
        explanation = get_or_create_explanation(assessment, language)
        return Response(ExplanationSerializer(explanation).data)


class HistoryView(generics.ListAPIView):
    """GET /history — попытки (пагинация) + взвешенная сводка прогресса."""

    serializer_class = AttemptSummarySerializer

    def get_queryset(self):
        qs = ReadingAttempt.objects.filter(user=self.request.user).select_related("assessment")
        if doc := self.request.query_params.get("document"):
            qs = qs.filter(document_id=doc)
        return qs

    def list(self, request, *args, **kwargs):
        response = super().list(request, *args, **kwargs)
        recent = Assessment.objects.filter(attempt__user=request.user).order_by("-created_at")[:10]
        response.data["summary"] = scoring.weighted_summary(list(recent))
        response.data["streak_days"] = streak_days(request.user)
        return response


def streak_days(user) -> int:
    """Серия дней подряд с хотя бы одной завершённой попыткой (UTC)."""
    days = set(
        ReadingAttempt.objects.filter(user=user, status=ReadingAttempt.Status.COMPLETED)
        .values_list("created_at__date", flat=True)
    )
    today = timezone.now().date()
    day = today if today in days else today - timedelta(days=1)
    streak = 0
    while day in days:
        streak += 1
        day -= timedelta(days=1)
    return streak
