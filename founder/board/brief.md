# Board brief: SpeakCheck

You are reviewing a business idea. You cannot see any earlier conversation; this file is everything you know.

## The idea (from founder/idea.md)

- **What it is:** an iOS app where the user reads their own English text aloud and gets a 0–100 pronunciation score for every word and every sound, with explanations of the mistakes in Russian.
- **Who it is for:** Russian-speaking adults in the CIS, starting with Kyrgyzstan, who can read English but are not confident speaking it: students preparing for IELTS or job interviews, IT and office workers who present or take calls in English, people preparing to relocate.
- **What it sells, at what price:** the core loop — upload your own document (PDF, Word, TXT or a photo of a page; text extraction happens on the phone) → read one fragment (≤40 words) aloud → get scores for accuracy, fluency, completeness and intonation, plus per-word and per-sound highlights → read an explanation of the mistakes in Russian → listen to a reference voice and retry the hard word. **Price is not decided.** The founder's working hypothesis (untested): free with a daily limit, plus a paid "Pro" subscription for unlimited practice. The price level is open.
- **Where and how:** iPhone only (iOS 17+), App Store in CIS countries. No paid marketing planned yet. Growth is meant to come from built-in sharing: a result card for Instagram/Telegram stories, a "challenge a friend" link (the friend reads the same text and the scores are compared side by side), a daily streak, a word of the day, and a personal list of difficult words. Works without registration (guest mode); Sign in with Apple is optional.

## Facts about the current state

- The product is already built: iOS app (SwiftUI) and a backend (Django) with automated tests passing; security review done.
- Not live yet: it still needs a server, a Microsoft Azure Speech key, a DeepSeek API key and an Apple Developer account.
- Scoring comes from Microsoft Azure Pronunciation Assessment (a third-party API); explanations come from DeepSeek (a third-party LLM). Both cost money per use; the exact cost per practice session has not been calculated.
- Audio is deleted from the server right after analysis by default.
- The app states that scores are a learning guide, not a certified CEFR/IELTS result.
- Solo founder. No marketing budget stated. No market size, customer acquisition cost or competitor data has been gathered yet.

## What is NOT known (do not invent it)

Market size, willingness to pay, competitor prices, unit cost per session, acquisition cost, retention. If you need one of these, name it as an open question.
