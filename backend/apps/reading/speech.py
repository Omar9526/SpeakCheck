"""POST /api/v1/speech — эталонное чтение текста живым голосом (MP3)."""
from django.conf import settings
from django.http import HttpResponse
from rest_framework import serializers
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from core.errors import APIError
from services import tts


class SpeechRequestSerializer(serializers.Serializer):
    text = serializers.CharField(max_length=settings.MAX_SEGMENT_CHARS, trim_whitespace=True)
    slow = serializers.BooleanField(default=False)
    voice = serializers.ChoiceField(choices=list(settings.ELEVENLABS_VOICES), default=settings.DEFAULT_TTS_VOICE)


class SpeechView(APIView):
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "speech"

    def post(self, request):
        s = SpeechRequestSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        try:
            audio = tts.synthesize(**s.validated_data)
        except tts.SynthesisFailed as e:
            raise APIError(e.code, "Озвучка сейчас недоступна.", 503) from e
        response = HttpResponse(audio, content_type="audio/mpeg")
        response["Cache-Control"] = "private, max-age=86400"
        return response
