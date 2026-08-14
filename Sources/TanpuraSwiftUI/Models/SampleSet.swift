import Foundation

/// A single playable string. kharaj/sa/pa/ni are recorded string names that
/// key into a SampleSet's `files`; `ma` is never recorded — it's always
/// derived at runtime by pitch-shifting Pa down two semitones (see
/// TanpuraVoice.setSampleSet), so it never appears in `files`.
enum StringName: String, CaseIterable {
    case kharaj, sa, pa, ni, ma
}

struct DerivePaSpec {
    let fromSet: String
    let semitones: Double
}

struct SampleSet {
    let key: String
    let label: String
    let root: String // recorded anchor note, e.g. "C#3" or "G#3"
    let files: [StringName: String] // StringName -> resource filename (no extension)
    let derivePa: DerivePaSpec?
}

/// Mirrors app.js's SAMPLE_SETS exactly, including the documented rationale
/// for deriving G#3's Pa from C#3's real Pa recording (+7 semitones) since
/// no Pa/Ni was ever recorded at the G#3 (female-register) anchor.
enum SampleSets {
    static let all: [String: SampleSet] = [
        "Cs3": SampleSet(
            key: "Cs3",
            label: "C#3",
            root: "C#3",
            files: [
                .kharaj: "Tanpura_Cs3_Kharaj",
                .sa: "Tanpura_Cs3_Sa",
                .pa: "Tanpura_Cs3_Pa",
                .ni: "Tanpura_Cs3_Ni",
            ],
            derivePa: nil
        ),
        "Cs3Alt": SampleSet(
            key: "Cs3Alt",
            label: "C#3 Alt",
            root: "C#3",
            files: [
                .kharaj: "Tanpura_Cs3Alt_Kharaj",
                .sa: "Tanpura_Cs3Alt_Sa",
                .pa: "Tanpura_Cs3Alt_Pa",
            ],
            derivePa: nil
        ),
        "Gs3": SampleSet(
            key: "Gs3",
            label: "G#3",
            root: "G#3",
            files: [
                .kharaj: "Tanpura_Gs3_Kharaj",
                .sa: "Tanpura_Gs3_Sa",
            ],
            derivePa: DerivePaSpec(fromSet: "Cs3", semitones: 7)
        ),
    ]

    /// Insertion order matters for anchor grouping and "first key wins" ties,
    /// same as Object.entries() iteration order in the JS version.
    static let order = ["Cs3", "Cs3Alt", "Gs3"]
}

/// A group of sample-set keys that share a recorded root note ("anchor"),
/// mirrors app.js's buildAnchorRoots()/ANCHOR_ROOTS.
struct AnchorRoot {
    let root: String
    let midi: Int
    let keys: [String]
}

enum AnchorRoots {
    static let all: [AnchorRoot] = {
        var byRoot: [String: [String]] = [:]
        for key in SampleSets.order {
            guard let set = SampleSets.all[key] else { continue }
            byRoot[set.root, default: []].append(key)
        }
        // Preserve first-seen order of roots (C#3 before G#3), matching the
        // JS Map's insertion-order iteration.
        var seenRoots: [String] = []
        for key in SampleSets.order {
            guard let set = SampleSets.all[key], !seenRoots.contains(set.root) else { continue }
            seenRoots.append(set.root)
        }
        return seenRoots.map { root in
            AnchorRoot(root: root, midi: Note.toMidi(root), keys: byRoot[root] ?? [])
        }
    }()

    /// Picks the anchor whose root MIDI is closest to `midi`. Ties fall to
    /// whichever anchor appears first (lower root) — same as nearestAnchor()
    /// in app.js, keeping the boundary at E3/F3 rather than F3/F#3.
    static func nearest(to midi: Int) -> AnchorRoot {
        var best = all[0]
        var bestDist = Int.max
        for anchor in all {
            let d = abs(midi - anchor.midi)
            if d < bestDist {
                bestDist = d
                best = anchor
            }
        }
        return best
    }

    /// The "alt" (male-voice) group: whichever anchor has more than one
    /// recorded sample-set key. Mirrors ALT_GROUP / ALT_BASE_KEY / ALT_ALT_KEY.
    static let altGroup: AnchorRoot? = all.first { $0.keys.count > 1 }
    static let altBaseKey: String? = altGroup?.keys.first { !$0.hasSuffix("Alt") }
    static let altAltKey: String? = altGroup?.keys.first { $0.hasSuffix("Alt") }
}

/// Reference range: A2 to E4 (1.5 octaves), matching app.js's MIN/MAX_KEY_MIDI.
enum KeyRange {
    static let minMidi = Note.toMidi("A2")
    static let maxMidi = Note.toMidi("E4")
}
