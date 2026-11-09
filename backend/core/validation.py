"""Общие проверки входных данных."""
import uuid


def parse_uuid(value) -> uuid.UUID | None:
    """UUID из строки клиента или None — вместо 500 на мусорном вводе."""
    if not isinstance(value, str):
        return None
    try:
        return uuid.UUID(value)
    except ValueError:
        return None
