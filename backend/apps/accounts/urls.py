from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from .views import AppleAuthView, GoogleAuthView, GuestAuthView, LogoutView, MeView

urlpatterns = [
    path("auth/apple", AppleAuthView.as_view()),
    path("auth/google", GoogleAuthView.as_view()),
    path("auth/guest", GuestAuthView.as_view()),
    path("auth/refresh", TokenRefreshView.as_view()),
    path("auth/logout", LogoutView.as_view()),
    path("me", MeView.as_view()),
]
