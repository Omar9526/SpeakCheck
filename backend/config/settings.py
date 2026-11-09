"""Настройки SpeakCheck backend. Все секреты — только из окружения (backend/.env)."""
from datetime import timedelta
from pathlib import Path

import environ

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env(
    DJANGO_DEBUG=(bool, False),
    DJANGO_ALLOWED_HOSTS=(list, ["localhost", "127.0.0.1"]),
)
environ.Env.read_env(BASE_DIR / ".env", overwrite=False)

SECRET_KEY = env("DJANGO_SECRET_KEY", default="dev-insecure-key-only-for-local-development-change-me")
DEBUG = env("DJANGO_DEBUG")
ALLOWED_HOSTS = env("DJANGO_ALLOWED_HOSTS")

INSTALLED_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "rest_framework",
    "apps.accounts",
    "apps.reading",
]

MIDDLEWARE = [
    "core.middleware.RequestIDMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.middleware.common.CommonMiddleware",
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
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.UserRateThrottle",
        "rest_framework.throttling.AnonRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "user": env("THROTTLE_USER", default="120/min"),
        "anon": env("THROTTLE_ANON", default="20/min"),
        "attempts": env("THROTTLE_ATTEMPTS", default="20/min"),
        "explanations": env("THROTTLE_EXPLANATIONS", default="20/min"),
    },
    "UNAUTHENTICATED_USER": None,
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(hours=1),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=60),
    "ROTATE_REFRESH_TOKENS": True,
    "USER_ID_FIELD": "id",
    "AUTH_HEADER_TYPES": ("Bearer",),
}

# Celery: без REDIS_URL задачи выполняются синхронно (dev/тесты).
REDIS_URL = env("REDIS_URL", default="")
CELERY_BROKER_URL = REDIS_URL or "memory://"
CELERY_TASK_ALWAYS_EAGER = not REDIS_URL
CELERY_TASK_EAGER_PROPAGATES = False
CELERY_TASK_ACKS_LATE = True
CELERY_TASK_TIME_LIMIT = 120

# Apple
APPLE_BUNDLE_ID = env("APPLE_BUNDLE_ID", default="kg.speakcheck.app")

# Azure Speech
AZURE_SPEECH_KEY = env("AZURE_SPEECH_KEY", default="")
AZURE_SPEECH_REGION = env("AZURE_SPEECH_REGION", default="")
AZURE_LOCALE = env("AZURE_LOCALE", default="en-US")

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
DAILY_ATTEMPTS_PER_USER = env.int("DAILY_ATTEMPTS_PER_USER", default=200)
DAILY_EXPLANATIONS_PER_USER = env.int("DAILY_EXPLANATIONS_PER_USER", default=100)
DATA_UPLOAD_MAX_MEMORY_SIZE = MAX_UPLOAD_MB * 1024 * 1024
FILE_UPLOAD_MAX_MEMORY_SIZE = 5 * 1024 * 1024

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
# В продакшне включить (обычно TLS терминирует прокси, тогда достаточно HSTS).
SECURE_SSL_REDIRECT = env.bool("SECURE_SSL_REDIRECT", default=False)
SECURE_HSTS_SECONDS = env.int("SECURE_HSTS_SECONDS", default=0)

# Логи без содержимого документов, аудио и ключей (ТЗ, раздел 11).
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "filters": {"request_id": {"()": "core.middleware.RequestIDLogFilter"}},
    "formatters": {"plain": {"format": "%(asctime)s %(levelname)s [%(request_id)s] %(name)s: %(message)s"}},
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "plain", "filters": ["request_id"]}},
    "root": {"handlers": ["console"], "level": "INFO"},
}
