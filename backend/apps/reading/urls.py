from django.urls import path

from . import views

urlpatterns = [
    path("documents", views.DocumentListCreateView.as_view()),
    path("documents/<uuid:pk>", views.DocumentDetailView.as_view()),
    path("segments/<uuid:segment_id>/attempts", views.AttemptCreateView.as_view()),
    path("attempts/<uuid:pk>", views.AttemptDetailView.as_view()),
    path("assessments/<uuid:assessment_id>/explanation", views.ExplanationView.as_view()),
    path("history", views.HistoryView.as_view()),
]
