# TypeParkinson presentation

Open `animation.html` in Chrome, Safari or Edge. It works offline and includes the actual app media. The revised cinematic film runs for 94 seconds, silently, so the team can narrate. It uses close-up keys, moving iPhones, masked type and individual letter transformations, with actual simulator footage.

- **Space**: pause or play
- **Left / right**: move between scenes
- **F**: fullscreen
- On-screen controls include a timeline and work with the keyboard.
- With Reduce Motion enabled, it opens paused as a slide presentation. Use the scene arrows to advance.

`TypeParkinson.mp4` is the delivery film: 1920×1080, 30 fps, H.264, no audio. `animation.template.html` is the editable source; `animation.html` is generated and self-contained.

## Reproduce

Requires Node 22+, Chrome and ffmpeg, with no npm dependencies.

```sh
node presentation/tools/pack.mjs
node presentation/tools/render.mjs test
node presentation/tools/render.mjs stills
node presentation/tools/render.mjs preview
node presentation/tools/render.mjs video
node presentation/tools/render.mjs poster
python3 presentation/tools/check-site.py
```

Set `CHROME` to a Chrome executable on other operating systems. The renderer uses a separate temporary browser profile and DevTools port 9237. Video frames are piped directly to ffmpeg; it doesn't fill the repository with thousands of PNGs. The preview command makes a full 94-second 960×540 / 15 fps draft in the ignored preview directory; video exports 1080p30. Set STILL_TIMES to a comma-separated list of seconds for detailed motion review. Absolute-time video seeking is awaited before capture. Encoding caps the bitrate to keep the film below 25 MB.

## Presenter notes

| Time | Point to explain |
| --- | --- |
| 0–7 | “See you soon” slips onto neighbouring keys. A person knows what they want to say; tremor and stiffness can make a tap miss that intention. |
| 7–14 | The Parkinson’s Foundation estimates 1.1 million people in the US live with Parkinson’s. |
| 14–22 | TypeParkinson builds a personal keyboard around how someone touches the screen. |
| 22–34 | Setup measures touch offset and spread. A two-dimensional Gaussian helps interpret the intended key. Illustrated dots and the keys stay put; the model learns around them. |
| 34–48 | The on-device decoder considers touch likelihood, word frequency, repeats, misses and swaps. The examples correspond to existing decoder tests. Revert is one tap away. |
| 48–60 | Show the actual Today, Practice and Voice screens. The app also includes Speak, medication reminders and a daily check. |
| 60–70 | Phone motion samples are windowed and analyzed in frequency space to describe shake strength and rate. This does not diagnose Parkinson’s. |
| 70–80 | The history helps a person discuss patterns with their clinician. PDF and CSV exports are available. A medication timing association is not proof of a treatment effect. |
| 80–86 | The keyboard works without Full Access. No servers, no stored typing. Optional sync goes to the user's own iCloud. |
| 86–94 | Atharv Sharma and Pranav Atreya, Congressional App Challenge. |

## Evidence and limits

- Population estimate: [Parkinson’s Foundation statistics](https://www.parkinson.org/understanding-parkinsons/statistics), checked October 23, 2026. This updates the older handoff’s “nearly one million” wording.
- App screens and clips are captured from the existing iPhone simulator installation. History, tremor and voice recordings are **sample data**, labeled in the film and website.
- Touch dots, the signal chart and correction keyboard are explanatory illustrations, not clinical results. The interactive website demo is a small fixed example, not the Swift decoder ported to JavaScript.
- The film makes no clinical effectiveness, diagnosis or disease-subtype claim.
- Still needed on physical hardware: system keyboard in other apps, App Group sharing, motion sensors, microphone and the “Took it” notification action.
