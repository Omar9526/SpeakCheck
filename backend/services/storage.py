"""Приватное хранилище аудио на диске сервера (MVP). Файлы не раздаются по HTTP."""
import os
import uuid
from pathlib import Path

from django.conf import settings


def _root() -> Path:
    root = Path(settings.PRIVATE_STORAGE_ROOT)
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    return root


def save_audio(user_id, data: bytes) -> str:
    key = f"{user_id}/{uuid.uuid4().hex}.wav"
    path = _root() / key
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with open(path, "wb") as f:
        f.write(data)
    os.chmod(path, 0o600)
    return key


def path_for(key: str) -> Path:
    path = (_root() / key).resolve()
    if _root().resolve() not in path.parents:
        raise ValueError("invalid storage key")
    return path


def delete(key: str | None) -> None:
    if not key:
        return
    try:
        path_for(key).unlink(missing_ok=True)
    except ValueError:
        pass


def delete_user_dir(user_id) -> None:
    folder = _root() / str(user_id)
    if folder.exists():
        for f in folder.iterdir():
            f.unlink(missing_ok=True)
        folder.rmdir()
