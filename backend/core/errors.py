"""Единый контракт ошибок: {"code", "message", "request_id"} (ТЗ, раздел 10)."""
from rest_framework import exceptions, status
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_handler

from core.middleware import request_id_var


class APIError(exceptions.APIException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_code = "bad_request"
    default_detail = "Некорректный запрос."

    def __init__(self, code=None, message=None, http_status=None):
        super().__init__(detail=message or self.default_detail, code=code or self.default_code)
        if http_status:
            self.status_code = http_status


_CODES = {
    exceptions.NotAuthenticated: ("not_authenticated", "Требуется вход."),
    exceptions.AuthenticationFailed: ("authentication_failed", "Сессия недействительна, войдите снова."),
    exceptions.PermissionDenied: ("forbidden", "Нет доступа."),
    exceptions.NotFound: ("not_found", "Не найдено."),
    exceptions.MethodNotAllowed: ("method_not_allowed", "Метод не поддерживается."),
    exceptions.Throttled: ("rate_limited", "Слишком много запросов. Попробуйте позже."),
    exceptions.UnsupportedMediaType: ("unsupported_media_type", "Неподдерживаемый формат."),
    exceptions.ParseError: ("parse_error", "Не удалось разобрать запрос."),
}


def error_response(code, message, http_status, extra=None):
    body = {"code": code, "message": message, "request_id": request_id_var.get()}
    if extra:
        body["details"] = extra
    return Response(body, status=http_status)


def exception_handler(exc, context):
    from django.http import Http404

    if isinstance(exc, Http404):
        exc = exceptions.NotFound()
    response = drf_handler(exc, context)
    if response is None:
        return None  # 500 — обрабатывает Django, без утечки деталей

    if isinstance(exc, APIError):
        code = exc.get_codes() if isinstance(exc.get_codes(), str) else "bad_request"
        return error_response(code, str(exc.detail), exc.status_code)
    if isinstance(exc, exceptions.ValidationError):
        return error_response("validation_error", "Проверьте введённые данные.", response.status_code, extra=response.data)
    for cls, (code, message) in _CODES.items():
        if isinstance(exc, cls):
            return error_response(code, message, response.status_code)
    return error_response("error", "Ошибка запроса.", response.status_code)
