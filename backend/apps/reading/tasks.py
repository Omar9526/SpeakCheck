from celery import shared_task

from .services import run_assessment


@shared_task(acks_late=True, max_retries=0)
def assess_attempt(attempt_id: str) -> None:
    run_assessment(attempt_id)
