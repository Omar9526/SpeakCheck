# SpeakCheck backend

Django 5 + DRF + PostgreSQL + Celery. Интеграции: Azure Speech Pronunciation Assessment, DeepSeek.
Ключи — только в `backend/.env` (шаблон `../.env.example`), в git и в iOS-приложение не попадают.

## Запуск (dev)

```bash
cd backend
uv sync
cp ../.env.example .env        # заполнить ключи
uv run python manage.py migrate
uv run python manage.py runserver 0.0.0.0:8000
uv run pytest                  # тесты
```

- Без `DATABASE_URL` используется SQLite (только разработка). Продакшн — PostgreSQL: `DATABASE_URL=postgres://...`.
- Без `REDIS_URL` Celery-задачи выполняются синхронно. С Redis: `uv run celery -A config worker -l info`.
- Без `AZURE_SPEECH_KEY` попытка честно завершается `failed / service_not_configured` — без выдуманных процентов.
- Без `DEEPSEEK_API_KEY` объяснения строятся по шаблону (`is_fallback: true`).

## API `/api/v1`

| Метод | Маршрут | Назначение |
|---|---|---|
| POST | `/auth/guest` | Гостевой аккаунт устройства → access/refresh |
| POST | `/auth/apple` | Вход по Apple identity token (серверная проверка JWKS); гость переносится в аккаунт |
| POST | `/auth/refresh` | Обновление токенов |
| GET/PATCH/DELETE | `/me` | Профиль, настройки (`keep_audio`, `explanation_language`, `voice_consent`), удаление аккаунта и всех данных |
| GET/POST | `/documents` | Список (пагинация) / создание из извлечённого на устройстве текста |
| GET/PATCH/DELETE | `/documents/{id}` | Документ с сегментами / исправление текста / удаление |
| POST | `/segments/{id}/attempts` | WAV 16 кГц mono (multipart `audio`), заголовок `Idempotency-Key` → 202 |
| GET/DELETE | `/attempts/{id}` | Статус `queued/processing/completed/failed`, результат, удаление |
| POST | `/assessments/{id}/explanation` | Объяснение DeepSeek (кеш, лимиты, fallback) |
| GET | `/history` | Попытки + взвешенная сводка + серия дней |

Ошибки: `{"code": "...", "message": "...", "request_id": "..."}`.

## Оценка (Azure)

- ≤ 30 с: `recognize_once` + miscue → пропуски/вставки размечает движок.
- \> 30 с: continuous mode (miscue не поддерживается) → пропуски не показываются, `completeness = null`.
- Итог = `PronScore`; `ProsodyScore` только en-US; фонемы в IPA; версия алгоритма в `score_version`; сырой ответ в `raw_provider_json`.
- Аудио удаляется сразу после анализа, если пользователь не включил `keep_audio`.
