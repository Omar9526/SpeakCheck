from celery import shared_task

from .services import run_assessment


@shared_task(acks_late=True, max_retries=0)
def assess_attempt(attempt_id: str) -> None:
    run_assessment(attempt_id)


@shared_task(ignore_result=True, max_retries=0)
def prefill_practice(user_id: str, topic: str) -> None:
    """Заранее готовит следующий текст тренировки, чтобы «Новый текст» открывался мгновенно."""
    from services import practice

    practice.prefill(user_id, topic)
