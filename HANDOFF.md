# TypeParkinson — handoff to the next assistant

You are taking over from Claude Code mid-project. Read this whole document before doing anything. It tells you what the app is, exactly where everything stands, the rules that matter, and the two tasks left to do. The user (GitHub: **BurTheBear**, student) is building this with partner **Pranav Atreya** (GitHub: **pranav-atreya10**) for the **Congressional App Challenge**. The user wants work that is genuinely impressive, not bland or template-looking.

---

## 1. What TypeParkinson is

An iPhone/iPad app (SwiftUI, iOS 26, Xcode 26.5) plus a **custom system keyboard extension**, for people with Parkinson's whose tremor and stiffness make typing hard.

Core loop: setup exercises measure how the person touches the screen → the app builds a personalised keyboard → an A/B "check" proves it helps versus a standard keyboard → the person turns the keyboard on and uses it in every app → daily checks and practice track how their hands are doing.

Feature list (all built, all in `main`):
- **Personal touch model** (`Shared/TouchModel.swift`): 2-D Gaussian of where touches land around the intended key (mean offset + sigma per axis), learned from setup and refined on-device as the person types. Stores only these numbers, never text.
- **Smart correction** (`Shared/IntentDecoder.swift`): when a word ends, Bayes' rule over candidate words — log P(touches | word) from the touch model via a DP alignment that can match, drop a tremor bounce, insert a missed letter or swap two letters — plus log P(word) from `Shared/WordList.swift` ranks (system dictionary as fallback). Verified by tests: "tje"→"the", "hellloo"→"hello", "tomorow"→"tomorrow", "teh"→"the"; correct words are left alone. One-tap revert chip.
- **Touch-pattern classifier** (`TypeParkinson/Model/PatternClassifier.swift`): on-device Gaussian naive Bayes over up to 9 measurements → probabilities for steady / shaky / slow-drifting / sudden-jumps (mixed if <50%). Tunes the keyboard. Parameters are expert-set, **not trained on patient data**. It describes touches; it **never diagnoses**.
- Keyboard extras: word suggestions (UITextChecker), saved phrases panel, brush filter, repeat (bounce) filter, offset correction, drift tolerance, slow hold-to-delete, Undo/Delete-word bar, key pop-up, themes (classic / high contrast / calm), large labels. Touches come from UIKit via `Shared/MultiTouchSurface.swift` with hardware timestamps.
- Tabs: **Today, Practice, Speak, Progress, Settings**.
- **Daily check**: 6 taps vs usual; can "adjust for today" without moving keys; "how does typing feel" rating.
- **Practice**: spiral tracing (deviation, smoothness, speed), rhythm tapping (taps/10 s, evenness, accuracy), typing practice (WPM, accuracy), **tremor meter** (10 s CoreMotion at 100 Hz, Hann window + DFT → dominant shake frequency in Hz and amplitude in mg; rest vs arm-out), **voice volume** (mic loudness vs a "loud zone", inspired by LSVT LOUD speech therapy).
- **Speak**: type with the personal keyboard, text-to-speech, saved phrases, full-screen **communication card** ("I have Parkinson's. Please give me a little extra time.").
- **Medication**: schedule + reminders with an actionable **"Took it"** notification button that logs doses even when the app is closed.
- **Progress**: achievements, insights (week-over-week change, steadiest time of day, **steadiest window after a dose**, feelings vs numbers), touch-pattern card, charts per measure, **PDF report + CSV export** for a care team.
- Siri/Shortcuts: "Start my TypeParkinson check", "Speak for me", "Measure my tremor", "Trace a spiral".
- Privacy: no servers; optional Sign in with Apple syncs profile + keyboard via the user's own iCloud key-value store; keyboard runs without Full Access.

## 2. Repository state (as of 2026-10-23)

- Upstream (Pranav's, the real one): https://github.com/pranav-atreya10/TypeParkinson — public.
- User's fork: https://github.com/BurTheBear/TypeParkinson
- **The user's account BurTheBear has NO push or merge access to Pranav's repo.** All changes must go: push a branch to the fork → open a PR into `pranav-atreya10/TypeParkinson:main` → Pranav merges. (`gh pr create --repo pranav-atreya10/TypeParkinson --base main --head BurTheBear:<branch>`)
- PR #5 (our big overhaul: smart correction, health tracking, "Aura" redesign) — **merged**.
- PR #6 (Pranav: body text sans-serif, an optional **Liquid Glass mode toggle** `AppModel.liquidGlassEnabled`, and a `BottomBar` component) — **merged**. Check whether `BottomBar` is actually shown anywhere now that the app uses a `TabView`; don't remove Pranav's work without asking.
- Local clone: `~/Desktop/TypeParkinson-CAC` (NOT `~/Desktop/typeParkinson`, which is an empty template).
- Local branches: `main` = `cd2d0d3` (up to date with upstream). Current branch: **`presentation`** (just created from main, no commits yet) — do the remaining work here.
- Remotes: `origin` = Pranav's repo, `fork` = https://github.com/BurTheBear/TypeParkinson.git
- Git identity: BurTheBear. End commit messages with a co-author line for whichever assistant did the work.

## 3. Build, test, run

```bash
cd ~/Desktop/TypeParkinson-CAC
xcodebuild -project TypeParkinson.xcodeproj -scheme TypeParkinson \
  -destination 'platform=iOS Simulator,id=4ED0F50B-CEC6-4B17-A835-70F32AAF01C7' \
  -derivedDataPath /tmp/tp-dd CODE_SIGNING_ALLOWED=NO build
xcodebuild test   # same flags; 55 Swift Testing tests, all passing on main
```
- Simulator: iPhone 17 Pro, UDID `4ED0F50B-CEC6-4B17-A835-70F32AAF01C7` (boot with `xcrun simctl boot <udid>`).
- Install/launch: `xcrun simctl install <udid> /tmp/tp-dd/Build/Products/Debug-iphonesimulator/TypeParkinson.app` then `xcrun simctl launch <udid> com.pranavatreya.typeparkinson -demoScreen home -demoTab today`
- Debug launch args (sample data): `-demoScreen onboarding|account|welcome|exercises|profile|proposal|check|compare|enable|home|recalResult|settings`, `-demoTab today|practice|speak|progress|settings`, `-demoSignedIn YES`. Debug builds also "simulate tremor" so mouse taps look shaky, and the tremor/voice exercises use sample recordings on the simulator.
- Clean status bar for footage: `xcrun simctl status_bar <udid> override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4`
- Record footage: `xcrun simctl io <udid> recordVideo --codec=h264 --force out.mp4` (stop with Ctrl-C / SIGINT).
- Tools on this Mac: `ffmpeg`, `node`, Google Chrome, Playwright's Chromium cache. No Playwright/Puppeteer npm package installed.

## 4. File map (most important)

- `Shared/` (app + keyboard): `Theme.swift` (tokens), `TouchModel.swift`, `IntentDecoder.swift`, `WordList.swift`, `TouchPattern.swift`, `KeyboardView.swift`, `KeyboardAccessories.swift` (suggestion bar, phrase panel), `KeyboardSettings.swift`, `KeyTouchInterpreter.swift`, `MultiTouchSurface.swift`, `KeyboardTheme.swift`, `WordSuggester.swift`, `QuickPhrases.swift`.
- `KeyboardExtension/KeyboardViewController.swift` — system keyboard, smart correction + on-device learning.
- `TypeParkinson/Model/` — `AppModel`, `ActivityStore` (history + sample data), `TextComposer`, `PatternClassifier`, `MotorAnalysis`, `SensorAnalysis` + `SensorRecorders` (tremor FFT, voice), `Insights` (+ achievements), `Medication`, `Speaker`, `ReportBuilder`, `Routing` (tabs, Siri intents, notification router).
- `TypeParkinson/Views/` — `Aura.swift` + `DesignKit.swift` (design system), `HomeScreens.swift` (Today), `PracticeViews.swift`, `SensorSessions.swift`, `SpeakView.swift`, `ProgressViews.swift`, `CareViews.swift`, `AccountScreens.swift` (Settings), `OnboardingScreens.swift`, setup flow files.
- `TypeParkinsonTests/SmartFeatureTests.swift` + `KeyboardTests.swift`.
- `docs/` — GitHub Pages site (`index.html`, `privacy.html`, `support.html`, `style.css`). The app links to `https://pranav-atreya10.github.io/TypeParkinson/privacy.html` and `/support.html` — keep those working.
- `typeparkinson-mockup/`, `TypeParkinson Website Design/` — Pranav's older Claude Design mockups (broadsheet/newspaper style). **The user rejected the newspaper style** — don't reuse it.
- Root also has Pranav's earlier `typeparkinson-animation-dark.mp4` / `-light.mp4` (v1 animations) — look at them, but the new animation should be far better.

## 5. Design system ("Aura") — match this in the animation and website

Look: cool light ground, white cards, a **living mesh-gradient "Aura"** as the signature, one electric blue, one colour per activity, SF Pro Rounded (heavy) for display + numbers, SF Pro for reading. On the web use `"SF Pro Rounded", ui-rounded, "Nunito", system-ui` for display and `-apple-system, "Inter", system-ui` for body (or a Google Font like "Nunito"/"DM Sans" as fallback).

Colours (light mode hex):
- Background `#F3F4F8`, card `#FFFFFF`, surface `#EEF0F5`, text `#0E1424`, secondary text `#5B6377`, divider `#E3E6EE`, ink (behind Aura) `#0A0F1F`
- Accent (keyboard / daily check) `#2F5BFF` (dark-mode `#6E8EFF`)
- Positive `#0B9A74`, warning `#D92D63`
- Activities: spiral `#00A0A0`, tapping `#FF5F33`, typing `#DB2F78`, speak `#0F9D63`, tremor `#6E4DFF`, voice `#E89400`, medication `#168BD0`
- Activity card gradients: spiral `#0FB5AE→#0A6E8A`, tapping `#FF7A45→#D9364F`, typing `#F0468E→#8E2BB8`, tremor `#7D5CFF→#3B2BB8`, voice `#FFB020→#F06A1F`
- Aura mesh (3×3, slowly animated), "neutral" mood colours: `#0A0F1F, #2F5BFF, #16123F, #6E4DFF, #3D7BFF, #16B8C8, #0A0F1F, #3424A0, #0A0F1F`. "Calm": `#0A0F1F, #1E46FF, #0C1A44, #14C2BC, #3D6BFF, #3FE0B5, #0A0F1F, #1F3FB8, #0A0F1F`. "Restless": `#0A0F1F, #FF5F33, #2A0F2E, #DB2F78, #FF8A3D, #FFC94D, #0A0F1F, #7A1F4A, #0A0F1F`.
- Daily rings: Check `#5C8BFF`, Practice `#2BE0C8`, Voice `#FFC94D`.
- Radii: cards 26, hero 34, controls 16 (primary buttons are pills), keys 8. Glass (frosted, translucent white) for secondary controls on the Aura.
- Tone of copy: warm, plain, short, encouraging; never "Welcome to…", no hype words, no emoji as decoration.

## 6. Hard rules (do not break)

1. **Never claim the app detects, diagnoses or classifies Parkinson's or its subtype.** It measures and describes touches, movement and voice. Use "touch pattern", "shake rate", "a record to share with your doctor". (App Store guideline 1.4.1 / FDA SaMD; also judges will ask.)
2. **Don't invent numbers.** Safe stat with source: ~1 million people in the U.S. live with Parkinson's, expected 1.2 million by 2030 (Parkinson's Foundation). Any other stat needs a cited source. App numbers shown on screen come from the demo/sample data — fine for a demo, label as such if presented as results.
3. Accessibility is the point: big targets, high contrast, Reduce Motion respected.
4. Don't push to Pranav's repo directly (you can't); use fork + PR. Don't merge on Pranav's behalf.
5. Keep `docs/privacy.html` and `docs/support.html` at those URLs.

## 7. TASK A (top priority): a VERY good presentation animation

The user wants a cinematic explainer/promo they can **play when presenting** to Congressional App Challenge judges. Make this the best thing in the project.

Deliverables (put in `presentation/` on the `presentation` branch):
- `presentation/animation.html` — self-contained, 1920×1080 (16:9), scales to fit any screen, plays in real time, **Space** = pause/play, **←/→** = jump scenes, **F** = fullscreen. No external network needed except optional Google Fonts.
- `presentation/TypeParkinson.mp4` — 1080p, 30 fps, H.264, ~75–100 s, under ~25 MB, silent (they will narrate) — optionally also a version with royalty-free music only if the user supplies a track.

Recommended technique (deterministic, renders perfectly to video):
- Write the whole animation as a pure function `render(t)` (seconds) that sets every element's style from `t` (no CSS transitions/keyframes, no `Math.random` — use a seeded PRNG). Expose `window.__render(t)`; in live mode drive it with `requestAnimationFrame`.
- Render to MP4: launch Chrome headless with `--remote-debugging-port=9222 --window-size=1920,1080 --hide-scrollbars`, connect over the DevTools WebSocket with a tiny Node script (Node has a built-in `WebSocket`), and for each frame: `Runtime.evaluate("__render(t)")` → `Page.captureScreenshot` (png) → write `frames/%05d.png`. Then `ffmpeg -framerate 30 -i frames/%05d.png -c:v libx264 -pix_fmt yuv420p -crf 18 -movflags +faststart TypeParkinson.mp4`. For embedded `<video>` footage, set `video.currentTime = t - sceneStart` and await `seeked` before capturing.
- **Use real app footage** inside an iPhone frame (it's far more convincing than fake UI). Record with `simctl io recordVideo` (see §3), convert to constant 30 fps and ~600 px wide: `ffmpeg -i in.mp4 -vf "fps=30,scale=600:-2" -c:v libx264 -crf 20 -an clip.mp4`. Good clips: Today screen scrolling (hero Aura + rings + insights), Speak typing "tje" + space → "The" with the revert chip, Tremor meter run → result with the Hz chart, Voice volume rising into the loud zone, Practice tab gradient tiles, Progress hero + achievements, onboarding pages.

Storyboard (~90 s; adjust freely if you have a better idea, but keep the arc: problem → product → how it works → proof → impact):
1. **0–7 s Cold open (black).** The line "Typing should be easy." types itself letter by letter… then the letters start to shake and land on neighbouring keys: "Typimg shpuld be eaay." Hold. Kinetic type, white on ink.
2. **7–14 s The problem.** "Nearly 1 million Americans live with Parkinson's." (cite: Parkinson's Foundation, small caption). Then "For many, every tap is a guess." Subtle tremor-jitter on the text.
3. **14–22 s Reveal.** The Aura mesh gradient blooms open from the centre; wordmark **TypeParkinson** (rounded heavy, white) + tagline "A keyboard that learns your hands."
4. **22–34 s It learns your touch.** A big glowing key (e.g. "h") with dozens of touch dots landing low-right of it (seeded), then a soft Gaussian ellipse fades in around the cloud with label "Your personal touch model". Then the keyboard "reads" the touches back onto the right key (dots slide to centre, key lights blue).
5. **34–48 s It works out what you meant.** Large keyboard; animated taps type "tje" (dots land, letters appear), space pressed → word morphs to "the" with a satisfying spring + check; quick montage "hellloo → hello", "tomorow → tomorrow", "teh → the". Caption: "Smart correction — on your iPhone, learning every time you type."
6. **48–60 s The app.** iPhone frame slides in playing real footage of Today; feature callouts float in around it with their activity colours: Daily check · Spiral · Rhythm tapping · Tremor meter · Voice · Speak · Medication.
7. **60–70 s Tremor meter.** Live waveform draws across → morphs into frequency bars with the peak at ~5 Hz highlighted; caption "Motion sensors + Fourier analysis: how much the hand shakes, and how fast." Footnote "A measurement, not a diagnosis."
8. **70–80 s Insight for the doctor.** Insight card "Steadiest 1–3 hours after a dose — worth showing your doctor." + a PDF report card flying out. Caption "Patterns you can take to your care team."
9. **80–86 s Privacy.** Three short lines with icons: "On-device." "No servers." "Never saves what you type."
10. **86–94 s End card.** Aura background, wordmark, "A keyboard that learns your hands.", "Built by BurTheBear & Pranav Atreya for the Congressional App Challenge" — **ask the user for the exact names they want shown before finalising** — and the website URL.

Craft notes: one strong motion idea per scene; spring/ease-out curves (no linear slides); generous negative space; big type (display 96–160 px); consistent Aura palette; motion-blur-free but smooth (30 fps); avoid stock-template looks (no generic icon grids, no purple-gradient clichés beyond the Aura itself, no emoji); respect `prefers-reduced-motion` in the live HTML (offer a static/slide mode).

## 8. TASK B: the website (`docs/` → GitHub Pages)

Replace `docs/index.html` (+ `docs/style.css` or a new CSS file) with a polished landing page in the Aura style. Keep `privacy.html` and `support.html` (restyle them to match if time allows).
Sections: hero (animated CSS/Canvas mesh gradient, wordmark, one-line pitch, the MP4 or a looping clip, App Store-style CTA placeholder "Coming soon" — **don't link to a store listing that doesn't exist**) → the problem → how it works (measure → build → check → type anywhere) → smart correction demo (nice: a tiny interactive web keyboard where typing "tje" + space shows the correction) → the toolkit (practice activities with their gradients) → for care teams (insights + PDF report) → privacy → team → footer (privacy, support links). Use real simulator screenshots (`xcrun simctl io <udid> screenshot file.png`) in iPhone frames. Fully responsive (phone width, 16 px gutters, no horizontal scroll), accessible (alt text, contrast ≥ 4.5:1, focus styles), fast (compress images/video; MP4 ≤ ~25 MB, or host the large file elsewhere and keep a smaller loop in the repo).

## 9. Finishing up

1. Commit on `presentation` (`presentation/` + `docs/` changes + this handoff can be deleted or kept).
2. `git push -u fork presentation`
3. Open a PR into `pranav-atreya10/TypeParkinson` main describing the animation and site; tell the user Pranav must merge it, then enable GitHub Pages (Settings → Pages → deploy from branch `main`, folder `/docs`) if not already on.
4. Still never tested on a real iPhone: the system keyboard inside other apps, App Group sharing, real motion sensors, microphone, "Took it" notification action. Mention this to the user as the next step after the presentation work.

## 10. Where we stopped

The previous assistant had just: pulled main (PR #6), confirmed it builds, created branch `presentation`, and started booting the simulator to record footage (Task A, step "record real app footage"). Nothing for Task A or B has been written yet. Start there.
