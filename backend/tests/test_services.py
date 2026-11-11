import json
from unittest import mock

import pytest

from services import azure_speech, deepseek, scoring
from tests import azure_samples


def test_normalize_short_maps_azure_fields():
    r = azure_speech.normalize_short(azure_samples.short_payload())
    assert r.overall == 85.3 and r.prosody == 79.0
    assert r.words[0]["start_ms"] == 100 and r.words[0]["end_ms"] == 400  # 100-нс тики → мс
    assert r.words[0]["phonemes"] == [{"phoneme": "l", "score": 98.0}, {"phoneme": "ɝ", "score": 90.0}]


def test_missing_prosody_stays_none():
    r = azure_speech.normalize_short(azure_samples.short_payload(prosody=False))
    assert r.prosody is None


def test_no_words_means_no_speech():
    with pytest.raises(azure_speech.AssessmentFailed) as e:
        azure_speech.normalize_short({"NBest": [{"PronunciationAssessment": {}, "Words": []}]})
    assert e.value.code == "no_speech"


def test_continuous_weighted_without_miscue():
    r = azure_speech.normalize_continuous(azure_samples.continuous_payloads())
    assert r.completeness is None  # miscue в continuous mode не поддерживается
    assert all(w["error_type"] != "Omission" for w in r.words)
    assert len(r.words) == 40 and [w["index"] for w in r.words] == list(range(40))
    assert r.overall == round((90 * 10 + 60 * 30) / 40, 1)
    assert r.score_version == azure_speech.SCORE_VERSION_CONTINUOUS


def test_assess_requires_configuration(settings):
    settings.AZURE_SPEECH_KEY = ""
    with pytest.raises(azure_speech.AssessmentFailed) as e:
        azure_speech.assess("/tmp/x.wav", "hi", 1000)
    assert e.value.code == "service_not_configured"


def test_weighted_summary():
    s = scoring.weighted_summary([
        {"overall": 90, "accuracy": None, "assessed_word_count": 10},
        {"overall": 50, "accuracy": None, "assessed_word_count": 30},
    ])
    assert s["overall"] == 60.0 and s["accuracy"] is None and s["word_count"] == 40


def test_deepseek_schema_validation_trims_and_filters():
    data = deepseek.validate({
        "summary": " ok ", "encouragement": 5,
        "tips": [{"word": "fun", "issue": "a", "explanation": "b", "exercise": "c"}, {"word": 1}, "junk"] + [
            {"word": f"w{i}", "issue": "a", "explanation": "b", "exercise": "c"} for i in range(10)],
    })
    assert data["summary"] == "ok" and data["encouragement"] == ""
    assert len(data["tips"]) <= deepseek.MAX_TIPS and data["tips"][0]["word"] == "fun"
    with pytest.raises(deepseek.ExplanationError):
        deepseek.validate({"tips": []})


def test_deepseek_request_and_retry_on_empty(settings):
    settings.DEEPSEEK_API_KEY = "k"
    good = {"summary": "s", "tips": [], "encouragement": "e"}
    responses = [
        mock.Mock(status_code=200, json=lambda: {"choices": [{"message": {"content": "  "}}]}),
        mock.Mock(status_code=200, json=lambda: {"choices": [{"message": {"content": json.dumps(good)}}]}),
    ]
    with mock.patch("services.deepseek.requests.post", side_effect=responses) as post:
        out = deepseek.explain("Hello", {"overall": 80}, [{"word": "hello", "score": 50, "error_type": "Mispronunciation"}])
    assert out == good and post.call_count == 2
    body = post.call_args.kwargs["json"]
    assert body["response_format"] == {"type": "json_object"} and body["max_tokens"] <= 1000
    assert "json" in body["messages"][0]["content"]
    sent = json.loads(body["messages"][1]["content"])
    assert sent["problem_words"][0]["word"] == "hello"  # аудио и лишние данные не отправляются


def test_deepseek_http_error_raises(settings):
    settings.DEEPSEEK_API_KEY = "k"
    with mock.patch("services.deepseek.requests.post", return_value=mock.Mock(status_code=500)):
        with pytest.raises(deepseek.ExplanationError):
            deepseek.explain("Hello", {}, [])


def _with_monotone(payload, prosody):
    best = payload["NBest"][0]
    best["PronunciationAssessment"]["ProsodyScore"] = prosody
    for w in best["Words"]:
        w["PronunciationAssessment"]["Feedback"] = {"Prosody": {"Intonation": {"ErrorTypes": ["Monotone"]}}}
    return payload


def test_monotone_hidden_when_intonation_is_good():
    from services import azure_speech
    from tests import azure_samples
    a = azure_speech.normalize_short(_with_monotone(azure_samples.short_payload(), 91.5))
    assert "Monotone" not in {w["error_type"] for w in a.words}
    assert {w["word"]: w["error_type"] for w in a.words}["fun"] == "Mispronunciation"


def test_monotone_kept_when_intonation_is_weak():
    from services import azure_speech
    from tests import azure_samples
    a = azure_speech.normalize_short(_with_monotone(azure_samples.short_payload(), 55.0))
    assert {w["word"]: w["error_type"] for w in a.words}["english"] == "Monotone"


def test_fallback_summary_plural():
    from services.deepseek import _words_ru
    assert [_words_ru(n) for n in (1, 2, 4, 5, 11, 12, 21, 22, 25)] == [
        "слово", "слова", "слова", "слов", "слов", "слов", "слово", "слова", "слов"]
