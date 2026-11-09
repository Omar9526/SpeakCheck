from django.urls import include, path

from apps.reading.challenges import challenge_landing

urlpatterns = [
    path("api/v1/", include("apps.accounts.urls")),
    path("api/v1/", include("apps.reading.urls")),
    path("health", include("core.urls")),
    path("c/<str:code>", challenge_landing),
]
