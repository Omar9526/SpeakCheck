"""POST /api/v1/practice/next {topic} — следующий персональный текст для бесконечной тренировки."""
from django.db import transaction
from rest_framework import serializers
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from services import practice


class NextSerializer(serializers.Serializer):
    topic = serializers.ChoiceField(choices=list(practice.TOPICS), default="surprise")


class PracticeNextView(APIView):
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "practice"

    def post(self, request):
        s = NextSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        text, level = practice.next_text(request.user, s.validated_data["topic"])
        # Пока человек читает — в фоне готовим следующий текст.
        from .tasks import prefill_practice

        transaction.on_commit(lambda: prefill_practice.delay(str(request.user.id), s.validated_data["topic"]))
        return Response({
            "id": str(text.id),
            "title": text.title,
            "text": text.text,
            "level": level,
            "topic": s.validated_data["topic"],
            "topic_name": practice.TOPIC_NAMES[s.validated_data["topic"]],
            "focus_sound": text.focus or None,
            "focus_example": practice.SOUND_HINTS.get(text.focus) if text.focus else None,
        })
