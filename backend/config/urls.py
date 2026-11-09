from django.urls import include, path

from apps.reading.challenges import challenge_landing
from core.public import apple_app_site_association, privacy

urlpatterns = [
    path("api/v1/", include("apps.accounts.urls")),
    path("api/v1/", include("apps.reading.urls")),
    path("health", include("core.urls")),
    path("c/<str:code>", challenge_landing),
    path("privacy", privacy),
    path(".well-known/apple-app-site-association", apple_app_site_association),
]
