"""Публичные страницы без авторизации: политика конфиденциальности и файл для Universal Links."""
from django.conf import settings
from django.http import HttpResponse, JsonResponse, HttpResponseNotFound

PRIVACY_HTML = """<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SpeakCheck — политика конфиденциальности</title>
<style>
body{margin:0;font-family:-apple-system,system-ui,sans-serif;background:#101C32;color:#F8FAFC;line-height:1.6}
main{max-width:720px;margin:0 auto;padding:32px 20px}
h1{font-size:28px} h2{font-size:19px;margin-top:28px} p,li{color:#CBD5E1}
</style></head><body><main>
<h1>Политика конфиденциальности SpeakCheck</h1>
<p>SpeakCheck помогает тренировать английское произношение: вы читаете свой текст вслух и получаете оценку по каждому слову.</p>

<h2>Какие данные мы обрабатываем</h2>
<ul>
<li><b>Текст документов</b>, которые вы загрузили. Сам файл (PDF, DOCX, фото) не покидает устройство — на сервер отправляется только извлечённый текст.</li>
<li><b>Запись голоса</b> фрагмента, который вы читаете. Она нужна только для оценки произношения.</li>
<li><b>Результаты оценок</b> и история попыток — чтобы показывать прогресс.</li>
<li><b>Идентификатор аккаунта</b>: анонимный (гостевой режим) или от «Войти через Apple». Мы не получаем ваш пароль Apple.</li>
</ul>

<h2>Как долго хранится запись голоса</h2>
<p>По умолчанию запись удаляется сразу после анализа. Если в настройках вы включили «Хранить аудио», запись хранится до тех пор, пока вы её не удалите.</p>

<h2>Кому передаются данные</h2>
<ul>
<li><b>Microsoft Azure AI Speech</b> — запись и эталонный текст фрагмента для оценки произношения.</li>
<li><b>DeepSeek</b> — эталонный текст и оценки слов (без записи голоса) для объяснения ошибок на русском языке.</li>
</ul>
<p>Мы не продаём данные, не показываем рекламу и не используем ваши тексты и записи для обучения моделей.</p>

<h2>Вызовы друзьям</h2>
<p>Если вы создаёте «Вызов другу», по ссылке будут видны начало текста (до 220 символов) и ваш общий балл. Ваше имя и записи не публикуются.</p>

<h2>Удаление данных</h2>
<p>В приложении: Профиль → «Удалить мои данные». Удаляются аккаунт, документы, попытки, оценки и записи.</p>

<h2>Контакты</h2>
<p>Вопросы о данных: {contact}</p>
</main></body></html>"""


def privacy(request):
    contact = settings.SUPPORT_EMAIL or "через страницу приложения в App Store"
    return HttpResponse(PRIVACY_HTML.replace("{contact}", contact))


def apple_app_site_association(request):
    """Universal Links: https://<домен>/c/<код> открывает приложение, если оно установлено."""
    if not settings.APPLE_TEAM_ID:
        return HttpResponseNotFound()
    app_id = f"{settings.APPLE_TEAM_ID}.{settings.APPLE_BUNDLE_ID}"
    return JsonResponse({"applinks": {"details": [{"appIDs": [app_id], "components": [{"/": "/c/*"}]}]}})
