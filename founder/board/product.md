# Product lens
Score: 6 | Vote: FUND IF

## What is strong
- **There is a clear "one thing":** read your own text aloud and see, per word and per sound, exactly what you got wrong, with the reason in Russian. That fits in one sentence, which is rare.
- **The experience is concrete and short:** read up to 40 words, get a score, read why, hear the reference, retry the hard word. The loop has a beginning and an end and ends in a retry, so it teaches by doing.
- **"Your own text" is a good product instinct.** The user practises the interview answer, the presentation or the IELTS essay they actually have, not a generic drill.
- **Craft in the parts nobody sees:** tests pass, a security review is done, audio is deleted by default, and the app says plainly that scores are not a certified CEFR/IELTS result. That honesty protects trust.
- **Low friction to try:** guest mode, no registration.

## What would kill it (the top 3, most dangerous first)
1. **The first five minutes ask the user to bring something.** Before any "wow", a new user has to find and upload a PDF, Word file or photo, wait for the text to be extracted, and pick a fragment. Many will leave before they hear their first score. The magic moment comes too late.
2. **Too many things at once.** Document import in four formats, four score types, per-sound breakdowns, explanations, reference voice, a streak, word of the day, a difficult-words list, share cards and friend challenges, all at launch from a solo founder. Each one is another place for the polish to slip, and together they blur the one thing.
3. **The experience hangs on two outside systems.** Every score goes phone → server → Azure → DeepSeek → phone. If it is slow, wrong, or the Russian explanation is vague or contradicts the score, the user blames SpeakCheck. Nobody has yet tested how long the wait is, how good the explanations are, or how the app behaves when one service fails.

## The questions I would ask the founder
- Describe second by second what a first-time user does from opening the app to their first score. How many seconds does it take, and how many taps?
- Can a new user get a score in under a minute without uploading anything, for example with a ready-made sample text?
- If you could keep only three features at launch, which three? What do you cut?
- How long does a score take to arrive on a typical CIS mobile connection? What does the user see while they wait, and what happens if Azure or DeepSeek fails?
- How do you know the Russian explanations are right and actually useful? Who has checked them?
- Is the share card something people would really post, or does a low score put them off sharing?
- How many real users have done the loop, and where did they get stuck?

## If FUND IF: the conditions
1. A first score within about 60 seconds of opening the app, using a built-in sample text; uploading your own document comes second.
2. Cut the launch to the core loop plus one reason to come back; streaks, word of the day and challenges wait until the loop is proven.
3. Measure the full round-trip time and design the waiting and failure states; review a sample of explanations for accuracy.
4. Watch at least 10 target users do their first session in person before going public, and fix what breaks.
