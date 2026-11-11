import uuid

from django.contrib.auth.base_user import AbstractBaseUser, BaseUserManager
from django.db import models


class UserManager(BaseUserManager):
    def create_user(self, **fields):
        user = self.model(**fields)
        user.set_unusable_password()
        user.save(using=self._db)
        return user


class User(AbstractBaseUser):
    """Пользователь: вход через Apple, Google или гостевой аккаунт устройства (без пароля)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    apple_sub = models.CharField(max_length=255, unique=True, null=True, blank=True)
    google_sub = models.CharField(max_length=255, unique=True, null=True, blank=True)
    is_guest = models.BooleanField(default=False)
    locale = models.CharField(max_length=16, default="ru")
    preferences = models.JSONField(default=dict, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    USERNAME_FIELD = "id"
    objects = UserManager()

    def __str__(self):
        return f"User({self.id})"
