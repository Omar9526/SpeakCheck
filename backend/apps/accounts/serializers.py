from rest_framework import serializers

from .models import User

ALLOWED_PREFERENCE_KEYS = {"explanation_language", "keep_audio", "voice_consent"}


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "is_guest", "locale", "preferences", "created_at"]
        read_only_fields = ["id", "is_guest", "created_at"]

    def validate_preferences(self, value):
        if not isinstance(value, dict) or set(value) - ALLOWED_PREFERENCE_KEYS:
            raise serializers.ValidationError("Недопустимые настройки.")
        return value

    def validate_locale(self, value):
        if value not in {"ru", "en", "ky"}:
            raise serializers.ValidationError("Неподдерживаемый язык.")
        return value


class AppleAuthSerializer(serializers.Serializer):
    identity_token = serializers.CharField(max_length=4096)
    locale = serializers.CharField(max_length=16, required=False)
    # Гостевой аккаунт, данные которого нужно перенести в Apple-аккаунт.
    link_guest = serializers.BooleanField(default=True)
