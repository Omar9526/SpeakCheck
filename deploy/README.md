# Деплой сервера SpeakCheck

Один сервер с Docker: Caddy (HTTPS, Let's Encrypt) → Django/gunicorn, Celery-воркер, PostgreSQL 16, Redis 7.
Аудио хранится в приватном томе `audio` и удаляется сразу после анализа.

## Что нужно

- VPS: Ubuntu 22.04+, 2 vCPU / 2 ГБ RAM, открыты порты 80 и 443.
- Домен с A-записью на IP сервера, например `api.speakcheck.kg`.
- Ключи Azure Speech и DeepSeek.

## Первый запуск

```bash
# с Mac: ключ на сервер, затем настройка (Docker, фаервол 22/80/443, вход только по ключу, fail2ban)
ssh-copy-id <user>@<IP>
scp deploy/server-setup.sh <user>@<IP>:~ && ssh -t <user>@<IP> 'sudo bash ~/server-setup.sh <user> && passwd'
# на сервере
git clone git@github.com:Omar9526/SpeakCheck.git && cd SpeakCheck/deploy
cp .env.example .env
nano .env        # DOMAIN, DJANGO_SECRET_KEY и POSTGRES_PASSWORD (openssl rand -hex 32), ключи
docker compose up -d --build
curl https://$DOMAIN/health   # {"status": "ok"}
```

Миграции применяются автоматически при старте `web`.

## Обновление

```bash
cd SpeakCheck && git pull && cd deploy && docker compose up -d --build
```

## Полезное

| Задача | Команда |
|---|---|
| Логи API | `docker compose logs -f web` |
| Логи оценки | `docker compose logs -f worker` |
| Бэкап БД | `docker compose exec db pg_dump -U speakcheck speakcheck > backup.sql` |
| Проверка настроек | `docker compose exec web python manage.py check --deploy` |

## После деплоя

1. В `ios/project.yml` (конфигурация Release) указать `SC_API_BASE_URL: "https://<DOMAIN>"`.
2. Для Universal Links: заполнить `APPLE_TEAM_ID` в `.env` и добавить в приложение
   Associated Domains `applinks:<DOMAIN>` — тогда ссылки-вызовы `https://<DOMAIN>/c/<код>` открывают приложение.
3. В App Store Connect указать политику конфиденциальности: `https://<DOMAIN>/privacy`.
