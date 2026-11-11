"""Настройки SpeakCheck backend. Все секреты — только из окружения (backend/.env)."""
from datetime import timedelta
from pathlib import Path

import environ
from django.core.exceptions import ImproperlyConfigured

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env(
    DJANGO_DEBUG=(bool, False),
    DJANGO_ALLOWED_HOSTS=(list, ["localhost", "127.0.0.1"]),
)
environ.Env.read_env(BASE_DIR / ".env", overwrite=False)

SECRET_KEY = env("DJANGO_SECRET_KEY", default="dev-insecure-key-only-for-local-development-change-me")
DEBUG = env("DJANGO_DEBUG")
# В продакшне (DJANGO_ENV=production) запуск с ключом по умолчанию запрещён.
if env("DJANGO_ENV", default="development") == "production" and SECRET_KEY.startswith("dev-insecure"):
    raise ImproperlyConfigured("DJANGO_SECRET_KEY обязателен в продакшне")
ALLOWED_HOSTS = env("DJANGO_ALLOWED_HOSTS")

INSTALLED_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.staticfiles",
    "rest_framework",
    "rest_framework_simplejwt.token_blacklist",
    "apps.accounts",
    "apps.reading",
]

MIDDLEWARE = [
    "core.middleware.RequestIDMiddleware",
    "core.middleware.SecurityHeadersMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"

# PostgreSQL в продакшне (DATABASE_URL). Без переменной — SQLite для локальной разработки/тестов.
DATABASES = {"default": env.db("DATABASE_URL", default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}")}
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
AUTH_USER_MODEL = "accounts.User"

LANGUAGE_CODE = "ru"
TIME_ZONE = "UTC"
USE_TZ = True

# Приватное хранилище аудио (не раздаётся статикой). S3-совместимое — позже.
PRIVATE_STORAGE_ROOT = Path(env("PRIVATE_STORAGE_ROOT", default=str(BASE_DIR / "media" / "private")))

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": ["rest_framework_simplejwt.authentication.JWTAuthentication"],
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"],
    "DEFAULT_PAGINATION_CLASS": "core.pagination.Pagination",
    "PAGE_SIZE": 20,
    "EXCEPTION_HANDLER": "core.errors.exception_handler",
    # Только JSON: без HTML-интерфейса DRF (меньше поверхность для XSS/CSRF).
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_PARSER_CLASSES": ["rest_framework.parsers.JSONParser"],
    # Один доверенный прокси (Caddy) — IP клиента берётся из X-Forwarded-For корректно, подделка не помогает.
    "NUM_PROXIES": env.int("NUM_PROXIES", default=1),
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.UserRateThrottle",
        "rest_framework.throttling.AnonRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "user": env("THROTTLE_USER", default="120/min"),
        "anon": env("THROTTLE_ANON", default="20/min"),
        "guest": env("THROTTLE_GUEST", default="10/hour"),
        "attempts": env("THROTTLE_ATTEMPTS", default="20/min"),
        "explanations": env("THROTTLE_EXPLANATIONS", default="20/min"),
        "speech": env("THROTTLE_SPEECH", default="60/min"),
        "practice": env("THROTTLE_PRACTICE", default="30/min"),
    },
    "UNAUTHENTICATED_USER": None,
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(hours=1),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=60),
    "ROTATE_REFRESH_TOKENS": True,
    # Старый refresh-токен после обновления и после выхода больше не принимается.
    "BLACKLIST_AFTER_ROTATION": True,
    "ALGORITHM": "HS256",
    "USER_ID_FIELD": "id",
    "AUTH_HEADER_TYPES": ("Bearer",),
}

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"

# Celery: без REDIS_URL задачи выполняются синхронно (dev/тесты).
REDIS_URL = env("REDIS_URL", default="")
CELERY_BROKER_URL = REDIS_URL or "memory://"

# Счётчики лимитов запросов должны быть общими для всех процессов gunicorn —
# иначе каждый процесс считает свой лимит и защита ослабевает в N раз.
CACHES = {
    "default": {"BACKEND": "django.core.cache.backends.redis.RedisCache", "LOCATION": REDIS_URL}
    if REDIS_URL
    else {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}
}
if env("DJANGO_ENV", default="development") == "production" and not REDIS_URL:
    raise ImproperlyConfigured("REDIS_URL обязателен в продакшне (очередь оценки и общие лимиты запросов)")
CELERY_TASK_ALWAYS_EAGER = not REDIS_URL
CELERY_TASK_EAGER_PROPAGATES = False
CELERY_TASK_ACKS_LATE = True
CELERY_TASK_TIME_LIMIT = 120

# Публичный адрес для ссылок-вызовов и ссылка на App Store
PUBLIC_BASE_URL = env("PUBLIC_BASE_URL", default="http://localhost:8000")
APP_STORE_URL = env("APP_STORE_URL", default="https://apps.apple.com/")

# Apple
APPLE_BUNDLE_ID = env("APPLE_BUNDLE_ID", default="kg.speakcheck.app")
APPLE_TEAM_ID = env("APPLE_TEAM_ID", default="")

# Google: OAuth Client ID приложения (iOS) из Google Cloud Console; можно несколько через запятую.
GOOGLE_CLIENT_IDS = tuple(x.strip() for x in env("GOOGLE_CLIENT_IDS", default="").split(",") if x.strip())
SUPPORT_EMAIL = env("SUPPORT_EMAIL", default="")

# Azure Speech
AZURE_SPEECH_KEY = env("AZURE_SPEECH_KEY", default="")
AZURE_SPEECH_REGION = env("AZURE_SPEECH_REGION", default="")
AZURE_LOCALE = env("AZURE_LOCALE", default="en-US")
# Голоса для «Послушать»: пользователь выбирает один из трёх в профиле.
# ElevenLabs (если задан ключ) — основной; Azure — запасной, с похожим голосом того же пола.
ELEVENLABS_API_KEY = env("ELEVENLABS_API_KEY", default="")
ELEVENLABS_VOICES = {
    "bella": env("ELEVENLABS_VOICE_BELLA", default="hpp4J3VqNfWAUOO0d1Us"),
    "matilda": env("ELEVENLABS_VOICE_MATILDA", default="XrExE9yKIg1WjnnlVkGX"),
    "eric": env("ELEVENLABS_VOICE_ERIC", default="cjVigY5qzO86Huf0OWal"),
}
AZURE_TTS_VOICES = {
    "bella": "en-US-AvaMultilingualNeural",
    "matilda": "en-US-EmmaMultilingualNeural",
    "eric": "en-US-AndrewMultilingualNeural",
}
DEFAULT_TTS_VOICE = "bella"
ELEVENLABS_MODEL = env("ELEVENLABS_MODEL", default="eleven_multilingual_v2")

# DeepSeek
DEEPSEEK_API_KEY = env("DEEPSEEK_API_KEY", default="")
DEEPSEEK_MODEL = env("DEEPSEEK_MODEL", default="deepseek-flash")
DEEPSEEK_BASE_URL = env("DEEPSEEK_BASE_URL", default="https://api.deepseek.com")
DEEPSEEK_TIMEOUT = env.int("DEEPSEEK_TIMEOUT", default=20)

# Лимиты
MAX_UPLOAD_MB = env.int("MAX_UPLOAD_MB", default=25)
MAX_AUDIO_SECONDS = env.int("MAX_AUDIO_SECONDS", default=90)
MAX_AUDIO_BYTES = MAX_AUDIO_SECONDS * 16_000 * 2 + 4096
MAX_SEGMENT_WORDS = env.int("MAX_SEGMENT_WORDS", default=120)
MAX_SEGMENTS_PER_DOCUMENT = env.int("MAX_SEGMENTS_PER_DOCUMENT", default=500)
MAX_SEGMENT_CHARS = env.int("MAX_SEGMENT_CHARS", default=1500)
MAX_DOCUMENTS_PER_USER = env.int("MAX_DOCUMENTS_PER_USER", default=300)
DAILY_ATTEMPTS_PER_USER = env.int("DAILY_ATTEMPTS_PER_USER", default=200)
DAILY_EXPLANATIONS_PER_USER = env.int("DAILY_EXPLANATIONS_PER_USER", default=100)
DATA_UPLOAD_MAX_MEMORY_SIZE = MAX_UPLOAD_MB * 1024 * 1024
FILE_UPLOAD_MAX_MEMORY_SIZE = 5 * 1024 * 1024

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
# В продакшне включить (обычно TLS терминирует прокси, тогда достаточно HSTS).
SECURE_SSL_REDIRECT = env.bool("SECURE_SSL_REDIRECT", default=False)
SECURE_HSTS_SECONDS = env.int("SECURE_HSTS_SECONDS", default=0)
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "no-referrer"
X_FRAME_OPTIONS = "DENY"
# API на JWT без cookie-сессий — CSRF не нужен; HTTP→HTTPS перенаправляет Caddy (deploy/Caddyfile).
SILENCED_SYSTEM_CHECKS = ["security.W003", "security.W008"]

# Логи без содержимого документов, аудио и ключей (ТЗ, раздел 11).
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "filters": {"request_id": {"()": "core.middleware.RequestIDLogFilter"}},
    "formatters": {"plain": {"format": "%(asctime)s %(levelname)s [%(request_id)s] %(name)s: %(message)s"}},
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "plain", "filters": ["request_id"]}},
    "root": {"handlers": ["console"], "level": "INFO"},
}
