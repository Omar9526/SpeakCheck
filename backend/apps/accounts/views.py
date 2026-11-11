from django.db import transaction
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken
from rest_framework_simplejwt.tokens import RefreshToken

from core.errors import APIError
from services import apple, google

from .models import User
from .serializers import AppleAuthSerializer, GoogleAuthSerializer, UserSerializer


def tokens_for(user):
    refresh = RefreshToken.for_user(user)
    return {"access": str(refresh.access_token), "refresh": str(refresh), "user": UserSerializer(user).data}


class GuestRateThrottle(AnonRateThrottle):
    """Создание гостей ограничено по IP: иначе можно наплодить аккаунты и обойти дневные лимиты."""

    scope = "guest"


def revoke_all_tokens(user) -> None:
    for token in OutstandingToken.objects.filter(user=user):
        BlacklistedToken.objects.get_or_create(token=token)


class GuestAuthView(APIView):
    """POST /auth/guest — анонимный аккаунт устройства (гостевой режим, ТЗ 2)."""

    permission_classes = [permissions.AllowAny]
    authentication_classes = []
    throttle_classes = [GuestRateThrottle]

    def post(self, request):
        locale = request.data.get("locale") if isinstance(request.data, dict) else None
        if locale not in ("ru", "en", "ky"):
            locale = "ru"
        user = User.objects.create_user(is_guest=True, locale=locale)
        return Response(tokens_for(user), status=status.HTTP_201_CREATED)


class AppleAuthView(APIView):
    """POST /auth/apple — вход по Apple identity token с серверной проверкой.

    Если запрос пришёл с токеном гостя и link_guest=true, гостевые данные переносятся
    в Apple-аккаунт (или гость сам становится им, если аккаунта ещё нет).
    """

    permission_classes = [permissions.AllowAny]
    throttle_classes = [AnonRateThrottle]

    def post(self, request):
        data = AppleAuthSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        try:
            claims = apple.verify_identity_token(data.validated_data["identity_token"], data.validated_data["nonce"])
        except apple.AppleTokenError:
            raise APIError("invalid_apple_token", "Не удалось подтвердить вход через Apple.", 401)

        user = sign_in(request, "apple_sub", claims["sub"], data.validated_data)
        update_contact(user, email=claims.get("email") if _verified(claims) else None,
                       name=data.validated_data.get("full_name"))
        return Response(tokens_for(user))


class GoogleAuthView(APIView):
    """POST /auth/google — вход по Google ID token с серверной проверкой (как /auth/apple)."""

    permission_classes = [permissions.AllowAny]
    throttle_classes = [AnonRateThrottle]

    def post(self, request):
        data = GoogleAuthSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        try:
            claims = google.verify_id_token(data.validated_data["id_token"], data.validated_data["nonce"])
        except google.GoogleTokenError:
            raise APIError("invalid_google_token", "Не удалось подтвердить вход через Google.", 401)
        user = sign_in(request, "google_sub", claims["sub"], data.validated_data)
        update_contact(user, email=claims.get("email") if _verified(claims) else None, name=claims.get("name"))
        return Response(tokens_for(user))


def _verified(claims: dict) -> bool:
    # Apple присылает "true" строкой, Google — булевым значением.
    return str(claims.get("email_verified", "")).lower() == "true"


def update_contact(user: User, email: str | None, name: str | None) -> None:
    """Имя и email берутся из проверенного токена (имя Apple — от приложения); пустые значения не затирают старые."""
    fields = []
    if email and len(email) <= 254 and email != user.email:
        user.email, fields = email, fields + ["email"]
    name = (name or "").strip()[:150]
    if name and name != user.name:
        user.name, fields = name, fields + ["name"]
    if fields:
        user.save(update_fields=fields)


def sign_in(request, field: str, sub: str, data: dict) -> User:
    """Находит или создаёт аккаунт по идентификатору провайдера (apple_sub / google_sub).

    Если запрос пришёл с токеном гостя и link_guest=true: гость сам становится этим аккаунтом,
    либо его документы и попытки переносятся в уже существующий аккаунт.
    """
    guest = request.user if (request.user and request.user.is_authenticated and request.user.is_guest) else None
    with transaction.atomic():
        user = User.objects.filter(**{field: sub}).first()
        if user is None and guest and data["link_guest"]:
            setattr(guest, field, sub)
            guest.is_guest = False
            guest.save(update_fields=[field, "is_guest"])
            user = guest
        elif user is None:
            user = User.objects.create_user(**{field: sub}, locale=data.get("locale", "ru"))
        elif guest and data["link_guest"] and guest.id != user.id:
            from apps.reading.models import Document, ReadingAttempt

            Document.objects.filter(user=guest).update(user=user)
            ReadingAttempt.objects.filter(user=guest).update(user=user)
            guest.delete()
    return user


class LogoutView(APIView):
    """POST /auth/logout {refresh} — отзывает refresh-токен этого устройства."""

    def post(self, request):
        raw = request.data.get("refresh")
        if isinstance(raw, str):
            try:
                token = RefreshToken(raw)
                if str(token.get("user_id")) == str(request.user.id):
                    token.blacklist()
            except TokenError:
                pass  # уже недействителен — выход всё равно успешен
        return Response(status=status.HTTP_204_NO_CONTENT)


class MeView(APIView):
    """GET/PATCH/DELETE /me — профиль, настройки, удаление аккаунта со всеми данными."""

    def get(self, request):
        return Response(UserSerializer(request.user).data)

    def patch(self, request):
        s = UserSerializer(request.user, data=request.data, partial=True)
        s.is_valid(raise_exception=True)
        s.save()
        return Response(s.data)

    def delete(self, request):
        from apps.reading.services import delete_user_data

        delete_user_data(request.user)
        revoke_all_tokens(request.user)
        request.user.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
