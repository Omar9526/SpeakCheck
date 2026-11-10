from django.urls import path

from . import challenges, speech, views

urlpatterns = [
    path("documents", views.DocumentListCreateView.as_view()),
    path("documents/<uuid:pk>", views.DocumentDetailView.as_view()),
    path("segments/<uuid:segment_id>/attempts", views.AttemptCreateView.as_view()),
    path("attempts/<uuid:pk>", views.AttemptDetailView.as_view()),
    path("assessments/<uuid:assessment_id>/explanation", views.ExplanationView.as_view()),
    path("history", views.HistoryView.as_view()),
    path("speech", speech.SpeechView.as_view()),
    path("challenges", challenges.ChallengeCreateView.as_view()),
    path("challenges/<str:code>", challenges.ChallengeDetailView.as_view()),
]
