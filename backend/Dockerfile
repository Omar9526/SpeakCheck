FROM python:3.12-slim

# Azure Speech SDK требует OpenSSL, CA-сертификаты и ALSA-библиотеку на Linux.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libssl3 libasound2 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:0.9.7 /uv /usr/local/bin/uv

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY . .
RUN DJANGO_SECRET_KEY=build-only python manage.py collectstatic --noinput

RUN useradd --create-home --uid 1000 app \
 && mkdir -p /data/private && chown -R app:app /data /app
USER app

ENV PRIVATE_STORAGE_ROOT=/data/private
EXPOSE 8000
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3", "--timeout", "60", "--access-logfile", "-"]
