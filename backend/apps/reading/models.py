"""Модель данных ТЗ, раздел 9. Все ресурсы принадлежат user и изолированы по нему."""
import uuid

from django.conf import settings
from django.db import models


class Document(models.Model):
    class Source(models.TextChoices):
        PDF = "pdf"
        DOCX = "docx"
        TXT = "txt"
        IMAGE = "image"
        MANUAL = "manual"

    class Status(models.TextChoices):
        PROCESSING = "processing"
        READY = "ready"
        FAILED = "failed"

    # id может прийти от клиента (UUID, созданный офлайн) — так локальные и серверные id совпадают.
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="documents")
    filename = models.CharField(max_length=255)
    mime_type = models.CharField(max_length=100, blank=True)
    source = models.CharField(max_length=16, choices=Source.choices, default=Source.MANUAL)
    storage_key = models.CharField(max_length=255, blank=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.READY)
    # Документ создан из «Вызова другу» — для метрики «сколько вызовов приняли».
    challenge = models.ForeignKey("Challenge", on_delete=models.SET_NULL, null=True, blank=True,
                                  related_name="documents")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["user", "-created_at"])]

    @property
    def extracted_text(self) -> str:
        return "\n\n".join(s.reference_text for s in self.segments.all())


class ReadingSegment(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    document = models.ForeignKey(Document, on_delete=models.CASCADE, related_name="segments")
    sequence = models.PositiveIntegerField()
    reference_text = models.TextField()
    page_number = models.PositiveIntegerField(null=True, blank=True)

    class Meta:
        ordering = ["sequence"]


class ReadingAttempt(models.Model):
    class Status(models.TextChoices):
        QUEUED = "queued"
        PROCESSING = "processing"
        COMPLETED = "completed"
        FAILED = "failed"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="attempts")
    # SET_NULL: если текст фрагмента изменили, история попыток сохраняется.
    segment = models.ForeignKey(ReadingSegment, on_delete=models.SET_NULL, null=True, related_name="attempts")
    document = models.ForeignKey(Document, on_delete=models.CASCADE, related_name="attempts")
    reference_text = models.TextField()  # снимок эталона на момент записи
    audio_key = models.CharField(max_length=255, null=True, blank=True)
    duration_ms = models.PositiveIntegerField(default=0)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.QUEUED)
    failure_code = models.CharField(max_length=64, blank=True)
    score_version = models.CharField(max_length=64, blank=True)
    idempotency_key = models.CharField(max_length=64, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["user", "idempotency_key"], name="uniq_attempt_idempotency"),
        ]
        indexes = [models.Index(fields=["user", "-created_at"])]


class Assessment(models.Model):
    """Оценки — ровно то, что вернул Azure. null = метрика не вернулась (UI: «Недоступно»)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    attempt = models.OneToOneField(ReadingAttempt, on_delete=models.CASCADE, related_name="assessment")
    overall = models.FloatField(null=True)
    accuracy = models.FloatField(null=True)
    fluency = models.FloatField(null=True)
    completeness = models.FloatField(null=True)
    prosody = models.FloatField(null=True)
    assessed_word_count = models.PositiveIntegerField(default=0)
    raw_provider_json = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True)


class WordAssessment(models.Model):
    assessment = models.ForeignKey(Assessment, on_delete=models.CASCADE, related_name="words")
    index = models.PositiveIntegerField()
    word = models.CharField(max_length=128)
    start_ms = models.PositiveIntegerField(null=True)
    end_ms = models.PositiveIntegerField(null=True)
    score = models.FloatField(null=True)
    error_type = models.CharField(max_length=32, null=True)
    phonemes_json = models.JSONField(null=True)

    class Meta:
        ordering = ["index"]


class AIExplanation(models.Model):
    assessment = models.OneToOneField(Assessment, on_delete=models.CASCADE, related_name="explanation")
    model = models.CharField(max_length=64)
    language = models.CharField(max_length=8, default="ru")
    summary = models.TextField()
    tips_json = models.JSONField(default=list)
    encouragement = models.TextField(blank=True)
    is_fallback = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)


class Challenge(models.Model):
    """«Брось вызов другу»: короткий код → тот же текст и результат автора для сравнения."""

    code = models.CharField(max_length=12, unique=True)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="challenges")
    title = models.CharField(max_length=120)
    reference_text = models.TextField()
    owner_score = models.FloatField(null=True)
    opened_count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
