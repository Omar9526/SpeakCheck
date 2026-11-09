"""Ответы Azure в формате из документации Microsoft (NBest → PronunciationAssessment → Words → Phonemes)."""


def word(w, acc, err="None", offset=1_000_000, phonemes=None):
    item = {"Word": w, "Offset": offset, "Duration": 3_000_000,
            "PronunciationAssessment": {"AccuracyScore": acc, "ErrorType": err}}
    if phonemes:
        item["Phonemes"] = [{"Phoneme": p, "PronunciationAssessment": {"AccuracyScore": s}} for p, s in phonemes]
    return item


def short_payload(prosody=True, completeness=90.0):
    pa = {"AccuracyScore": 82.0, "FluencyScore": 88.0, "CompletenessScore": completeness, "PronScore": 85.3}
    if prosody:
        pa["ProsodyScore"] = 79.0
    return {
        "RecognitionStatus": "Success",
        "NBest": [{
            "Confidence": 0.93,
            "PronunciationAssessment": pa,
            "Words": [
                word("learning", 95, phonemes=[("l", 98), ("ɝ", 90)]),
                word("english", 91),
                word("is", 40, "Omission"),
                word("fun", 54, "Mispronunciation", phonemes=[("f", 30), ("ʌ", 80), ("n", 95)]),
                word("very", 70, "Insertion"),
            ],
        }],
    }


def continuous_payloads():
    def part(pron, acc, n_words, start):
        return {"NBest": [{
            "PronunciationAssessment": {"AccuracyScore": acc, "FluencyScore": 80, "PronScore": pron,
                                        "CompletenessScore": 100},
            "Words": [word(f"w{start + i}", acc, "Omission" if i == 0 and start else "None") for i in range(n_words)],
        }]}
    return [part(90, 90, 10, 0), part(60, 60, 31, 10)]
