# SpeakCheck

iOS-приложение для тренировки английского произношения: загрузите свой документ (PDF, DOCX, TXT, фото), прочитайте вслух и получите оценку 0–100 по каждому слову от Azure Speech, разбор ошибок на русском от DeepSeek и повтор проблемных слов.

> Оценки — учебный ориентир, а не сертифицированный тест CEFR.

## Структура

```
ios/        SwiftUI-приложение (Swift 6, iOS 17+, XcodeGen)
backend/    Django + DRF + PostgreSQL + Celery (Azure Speech, DeepSeek)
docs/       ТЗ, скриншоты, архитектура
```

## iOS

Требуется Xcode 26+ и [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd ios
xcodegen generate
open SpeakCheck.xcodeproj
# или из терминала:
xcodebuild -project SpeakCheck.xcodeproj -scheme SpeakCheck -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
```

Отладочные аргументы запуска (только Debug):
- `-demoData` — демо-документы и попытки (mock-данные из `Core/Preview`, в Release не попадают)
- `-screen import|review|document|reader|processing|result|word|history|settings` — открыть экран сразу

Скриншоты всех экранов: `ios/scripts/screenshots.sh <SIM_UDID> home result word ...` → `docs/screenshots/`.

## Backend

См. [backend/README.md](backend/README.md). Секреты — только в `backend/.env` (шаблон: `.env.example`).

## Этапы

| # | Этап | Статус |
|---|------|--------|
| 0 | Окружение (XcodeGen, uv, Python 3.12, gh) | ✅ |
| 1 | Дизайн-система, навигация, все экраны | ✅ |
| 2 | Импорт PDF/DOCX/TXT/фото, OCR, сегментация, запись WAV 16 кГц | ✅ (в коде, проверка на устройстве) |
| 3 | Django/DRF, PostgreSQL, Sign in with Apple, API, связка с iOS | ✅ (локально на SQLite; Postgres — при деплое) |
| 4 | Azure Pronunciation Assessment | ✅ код + тесты; нужен ключ Azure для живой проверки |
| 5 | DeepSeek-объяснения | ✅ код + тесты; нужен ключ DeepSeek |
| 6 | Вирусность: карточка для сторис, вызов другу (ссылка + лендинг), серия дней, слово дня, трудные слова | ✅ |
| 7 | Тесты, доступность, TestFlight | ⏳ |
