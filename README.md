# Tanpura (SwiftUI)

A native SwiftUI rewrite of [tanpuraweb](https://github.com/FlicksDaModdle/tanpuraweb),
styled with Liquid Glass (iOS 26). Two independently-tuned drone voices,
automatic register switching between recorded C#3/G#3 anchors, and a derived
"Ma" note — same behavior as the original Web Audio app, rebuilt on
AVFoundation.

## How the port maps to the original

| Web Audio (`app.js`)                          | SwiftUI / AVFoundation                                   |
|------------------------------------------------|------------------------------------------------------------|
| `AudioContext` + `AudioBufferSourceNode`        | `AVAudioEngine` + `AVAudioPlayerNode` per pluck            |
| `playbackRate` for tuning                       | `AVAudioUnitVarispeed.rate` per pluck's node chain          |
| Hand-rolled resample + WSOLA (derive Ma from Pa)| `AVAudioUnitTimePitch`, offline-rendered once and cached — does the same "shift pitch, keep duration" job natively |
| `localStorage` settings                         | `UserDefaults` + `Codable` (`SettingsStore`)                |
| Lookahead scheduler (`setTimeout` every 25ms)    | `DispatchSourceTimer` scheduling `AVAudioTime`-anchored buffers |
| `nearestAnchor()` register switching             | `AnchorRoots.nearest(to:)` — identical logic                |

The pluck sequence (2nd string → rest → Sa → rest → Kharaj → rest), the tempo
jitter ("vary tempos"), the attack-softening fade, and the G#3-Pa-derived-
from-C#3 logic are all ported 1:1.

## Project layout

```
Sources/TanpuraSwiftUI/
  Models/     Note.swift, SampleSet.swift, Settings.swift
  Audio/      SampleLibrary.swift, TanpuraVoice.swift, TanpuraEngine.swift
  Views/      ContentView.swift, KeyControlCard.swift, TanpuraPanelView.swift, ...
Resources/
  Audio/      the original .wav samples (renamed to drop "#", e.g. Tanpura_Cs3_Sa.wav)
  Info.plist
project.yml   XcodeGen spec — the source of truth for the Xcode project
.github/workflows/build.yml
```

There's no committed `.xcodeproj`. [XcodeGen](https://github.com/yonaskolb/XcodeGen)
generates it fresh from `project.yml` both locally and in CI — this avoids
checking in a giant, merge-conflict-prone `project.pbxproj`.

## Build locally

Requires **Xcode 26** (for the iOS 26 SDK / Liquid Glass APIs) and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
open TanpuraSwiftUI.xcodeproj
```

Then run on a Simulator or device from Xcode as usual.

## Build via GitHub Actions

`.github/workflows/build.yml` runs on every push to `main`: it installs
XcodeGen, generates the project, and builds an **unsigned Simulator build**.
That's as far as CI can go for free — Apple requires code signing for
anything installable on a real device or TestFlight, which means:

1. A paid Apple Developer Program account ($99/year)
2. A signing certificate + provisioning profile, stored as GitHub Secrets
3. Uncommenting the signing steps at the bottom of `build.yml`

Without that, CI still verifies the app builds correctly on every commit —
you'd just install it locally via Xcode (free, works on your own devices
with your personal Apple ID, just re-signs every 7 days).

## Known limitations / things worth testing on a real device

This was ported and reviewed carefully, but **I couldn't compile or run it**
in this environment (no Xcode/macOS available here) — there was no way to
verify it builds clean or sounds right. Treat it as a strong first draft, not
a finished, tested build. Specifically worth checking once you open it in
Xcode:

- **The scheduler** (`TanpuraVoice.tick()` / `AVAudioTime` offset math) is the
  piece most likely to need adjustment — sample-accurate scheduling across
  dynamically attached/detached nodes is the trickiest part of AVFoundation,
  and I'd want to see it running against real timing before trusting it.
- **`AVAudioUnitTimePitch` offline rendering** (`SampleLibrary.renderPitchShift`)
  should sound at least as good as the original's WSOLA, possibly better, but
  compare them side by side on the Ma note especially.
- **Xcode 26 availability on GitHub's `macos-15` runner** — if `setup-xcode`
  can't find Xcode 26, run `ls /Applications | grep Xcode` in a workflow step
  to see what's actually on the image and adjust `xcode-version` in
  `build.yml`.
- The Liquid Glass styling (`GlassCardModifier`, `.buttonStyle(.glass)`) uses
  the iOS 26 SDK APIs as I currently know them; double-check against the
  latest SwiftUI docs in Xcode, since this is a very new API surface.
