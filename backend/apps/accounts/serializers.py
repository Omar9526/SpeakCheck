from rest_framework import serializers

from .models import User

# Каждая настройка — строго своего типа и из допустимых значений.
PREFERENCE_VALIDATORS = {
    "explanation_language": lambda v: v in ("ru", "en"),
    "keep_audio": lambda v: isinstance(v, bool),
    "voice_consent": lambda v: isinstance(v, bool),
}


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "is_guest", "locale", "preferences", "created_at"]
        read_only_fields = ["id", "is_guest", "created_at"]

    def validate_preferences(self, value):
        if not isinstance(value, dict) or set(value) - set(PREFERENCE_VALIDATORS):
            raise serializers.ValidationError("Недопустимые настройки.")
        if not all(PREFERENCE_VALIDATORS[k](v) for k, v in value.items()):
            raise serializers.ValidationError("Недопустимое значение настройки.")
        return value

    def validate_locale(self, value):
        if value not in {"ru", "en", "ky"}:
            raise serializers.ValidationError("Неподдерживаемый язык.")
        return value


class AppleAuthSerializer(serializers.Serializer):
    identity_token = serializers.CharField(max_length=4096)
    # Исходный nonce: Apple кладёт в токен его SHA-256 — перехваченный токен нельзя использовать повторно.
    nonce = serializers.CharField(max_length=128)
    locale = serializers.ChoiceField(choices=["ru", "en", "ky"], required=False)
    # Гостевой аккаунт, данные которого нужно перенести в Apple-аккаунт.
    link_guest = serializers.BooleanField(default=True)
