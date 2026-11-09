# Источники цифр CFO (2026-11-09)

| Цифра | Значение | Источник / как получено |
|---|---|---|
| Azure Speech to Text, S1 real-time | $1.00 / час аудио | Официальный Azure Retail Prices API, регион westeurope, meter «S1 Speech To Text»: https://prices.azure.com/api/retail/prices?$filter=productName eq 'Azure Speech' and armRegionName eq 'westeurope' |
| Azure доп. функции (Pronunciation Assessment) | $0.30 / час аудио | Там же, meter «S1 Speech to Text Enhanced Feature Audio». Страница цен Azure противоречива (то «как обычный STT», то «add-on»), поэтому взят худший случай $1.00 + $0.30 = $1.30/ч |
| Бесплатный уровень Azure F0 | 5 часов аудио в месяц | https://azure.microsoft.com/en-us/pricing/details/cognitive-services/speech-services/ (в расчёт не включён — запас) |
| DeepSeek V4-Flash (`deepseek-flash`) | $0.14 вход / $0.28 выход за 1M токенов | **Оценка по сторонним обзорам** (официальная страница не отдала цены): https://dev.to/hassann/deepseek-v4-api-pricing-2j8f , https://pricepertoken.com/pricing-page/provider/deepseek . В расчёте взят консервативный верх $0.30 / $0.50 |
| Токенов на объяснение | ~1500 вход / ~500 выход | **Оценка** по промпту backend/services/deepseek.py (текст фрагмента + оценки слов + инструкция; ответ — JSON с 2–4 советами) |
| Длина попытки | 20 с | **Оценка**: фрагмент ≤ 40 слов при темпе ~120–150 слов/мин ≈ 16–20 с |
| Попыток у платящего | 150 / мес (5 в день) | **Оценка**: план совета — 3 фрагмента в день + повторы |
| Конверсия в платных | 5% (19 бесплатных на 1 платящего) | **Оценка** — главная неизвестная, проверить на реальных данных (`manage.py metrics`) |
| Попыток у бесплатного | 12 / мес | **Оценка** |
| Комиссия App Store | 15% | App Store Small Business Program (доход < $1M/год): https://developer.apple.com/app-store/small-business-program/ |
| Apple Developer Program | $99 / год | https://developer.apple.com/programs/ |
| VPS, домен | $10, $1.5 / мес | **Оценка** — заменить на реальный счёт хостинга |
| Цена Pro | $4.99 / мес | **Гипотеза** — заменить результатом `/founder-pricing` |
| Рост подписчиков (ramp) | 5 → 300 платящих за 12 мес | **Оценка** без данных; пересчитать после `/founder-consumer` и первых недель метрик |
