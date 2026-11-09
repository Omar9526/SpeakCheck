from django.conf import settings
from django.db import transaction
from rest_framework import serializers

from .models import AIExplanation, Assessment, Document, ReadingAttempt, ReadingSegment, WordAssessment


class SegmentSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)

    class Meta:
        model = ReadingSegment
        fields = ["id", "sequence", "reference_text", "page_number"]
        read_only_fields = ["sequence"]

    def validate_reference_text(self, value):
        text = value.strip()
        if not text:
            raise serializers.ValidationError("Пустой фрагмент.")
        if len(text) > settings.MAX_SEGMENT_CHARS:
            raise serializers.ValidationError(f"Фрагмент длиннее {settings.MAX_SEGMENT_CHARS} символов.")
        if len(text.split()) > settings.MAX_SEGMENT_WORDS:
            raise serializers.ValidationError(f"Фрагмент длиннее {settings.MAX_SEGMENT_WORDS} слов — разделите его.")
        return text


class DocumentListSerializer(serializers.ModelSerializer):
    segment_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = Document
        fields = ["id", "filename", "source", "status", "segment_count", "created_at", "updated_at"]


class DocumentSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)
    segments = SegmentSerializer(many=True)
    # Код вызова, из которого создан документ (необязательно). Неизвестный код молча игнорируется.
    challenge_code = serializers.CharField(max_length=12, required=False, write_only=True, allow_blank=True)

    class Meta:
        model = Document
        fields = ["id", "filename", "mime_type", "source", "status", "segments", "challenge_code",
                  "created_at", "updated_at"]
        read_only_fields = ["status", "created_at", "updated_at"]

    def validate_challenge_code(self, value):
        from .models import Challenge

        return Challenge.objects.filter(code=value).first() if value else None

    def validate_id(self, value):
        if Document.objects.filter(id=value).exists():
            raise serializers.ValidationError("Документ с таким id уже существует.")
        return value

    def validate_segments(self, value):
        if not value:
            raise serializers.ValidationError("Нужен хотя бы один фрагмент.")
        if len(value) > settings.MAX_SEGMENTS_PER_DOCUMENT:
            raise serializers.ValidationError("Слишком много фрагментов.")
        return value

    @transaction.atomic
    def create(self, validated):
        segments = validated.pop("segments")
        validated["challenge"] = validated.pop("challenge_code", None)
        doc = Document.objects.create(user=self.context["request"].user, **validated)
        _write_segments(doc, segments, existing={})
        return doc

    @transaction.atomic
    def update(self, doc, validated):
        segments = validated.pop("segments", None)
        validated.pop("id", None)
        validated.pop("challenge_code", None)
        for field, value in validated.items():
            setattr(doc, field, value)
        doc.save()
        if segments is not None:
            existing = {s.id: s for s in doc.segments.all()}
            keep = _write_segments(doc, segments, existing)
            # Удалённые фрагменты: попытки остаются в истории (segment=NULL).
            doc.segments.exclude(id__in=keep).delete()
        return doc


def _write_segments(doc, segments, existing):
    kept = []
    for seq, seg in enumerate(segments):
        sid = seg.get("id")
        if sid in existing:
            obj = existing[sid]
            obj.sequence = seq
            obj.page_number = seg.get("page_number")
            if obj.reference_text != seg["reference_text"]:
                obj.reference_text = seg["reference_text"]
            obj.save()
        else:
            if sid and ReadingSegment.objects.filter(id=sid).exists():
                sid = None  # чужой/повторный id — генерируем новый
            obj = ReadingSegment.objects.create(
                document=doc, sequence=seq, reference_text=seg["reference_text"],
                page_number=seg.get("page_number"), **({"id": sid} if sid else {}),
            )
        kept.append(obj.id)
    return kept


class WordSerializer(serializers.ModelSerializer):
    phonemes = serializers.JSONField(source="phonemes_json")

    class Meta:
        model = WordAssessment
        fields = ["index", "word", "start_ms", "end_ms", "score", "error_type", "phonemes"]


class AssessmentSerializer(serializers.ModelSerializer):
    words = WordSerializer(many=True)

    class Meta:
        model = Assessment
        fields = ["id", "overall", "accuracy", "fluency", "completeness", "prosody", "assessed_word_count", "words"]


class AttemptSerializer(serializers.ModelSerializer):
    assessment = serializers.SerializerMethodField()
    segment_id = serializers.UUIDField(read_only=True)
    document_id = serializers.UUIDField(read_only=True)

    class Meta:
        model = ReadingAttempt
        fields = ["id", "segment_id", "document_id", "duration_ms", "status", "failure_code",
                  "score_version", "created_at", "assessment"]

    def get_assessment(self, attempt):
        if attempt.status != ReadingAttempt.Status.COMPLETED:
            return None
        try:
            return AssessmentSerializer(attempt.assessment).data
        except Assessment.DoesNotExist:
            return None


class AttemptSummarySerializer(serializers.ModelSerializer):
    """Лёгкая версия для истории — без пословных данных."""

    overall = serializers.FloatField(source="assessment.overall", default=None)
    segment_id = serializers.UUIDField(read_only=True)
    document_id = serializers.UUIDField(read_only=True)

    class Meta:
        model = ReadingAttempt
        fields = ["id", "segment_id", "document_id", "status", "overall", "duration_ms", "created_at"]


class ExplanationSerializer(serializers.ModelSerializer):
    tips = serializers.JSONField(source="tips_json")

    class Meta:
        model = AIExplanation
        fields = ["summary", "tips", "encouragement", "is_fallback", "model", "language"]
