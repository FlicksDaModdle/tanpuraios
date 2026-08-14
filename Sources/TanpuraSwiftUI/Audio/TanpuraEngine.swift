import AVFoundation
import Combine

@MainActor
final class TanpuraEngine: ObservableObject {
    private let engine = AVAudioEngine()
    private let library = SampleLibrary()

    let voice1: TanpuraVoice
    let voice2: TanpuraVoice

    @Published var baseMidi: Int = Note.toMidi("C#3")
    @Published var fineCents: Double = 0
    @Published var tempoBpm: Double = 105 {
        didSet {
            let secondsPerPluck = 60.0 / tempoBpm
            voice1.pluckInterval = secondsPerPluck
            voice2.pluckInterval = secondsPerPluck
            save()
        }
    }
    @Published var varyTempo: Bool = true {
        didSet {
            voice1.varyTempo = varyTempo
            voice2.varyTempo = varyTempo
            save()
        }
    }
    @Published var altVoice: Bool = false {
        didSet { Task { await handleAltVoiceChange() } }
    }
    @Published private(set) var isReady = false
    @Published private(set) var startupError: String?

    var keyLabel: (name: String, octave: Int) {
        let parsed = Note.fromMidi(baseMidi)
        return (parsed.name, parsed.octave)
    }
    var canRaiseKey: Bool { baseMidi < KeyRange.maxMidi }
    var canLowerKey: Bool { baseMidi > KeyRange.minMidi }

    init() {
        let mainMixer = engine.mainMixerNode
        voice1 = TanpuraVoice(id: 1, engine: engine, destination: mainMixer)
        voice2 = TanpuraVoice(id: 2, engine: engine, destination: mainMixer)

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    func start() async {
        do {
            try engine.start()
        } catch {
            startupError = "Audio engine failed to start: \(error.localizedDescription)"
            print("Engine start failed: \(error)")
            return
        }

        let saved = SettingsStore.load()
        if let saved {
            baseMidi = min(KeyRange.maxMidi, max(KeyRange.minMidi, saved.baseMidi))
            fineCents = saved.fineCents
            tempoBpm = saved.tempoBpm
            varyTempo = saved.varyTempo
            if AnchorRoots.altAltKey != nil { altVoice = saved.altVoice }
        }
        voice1.pluckInterval = 60.0 / tempoBpm
        voice2.pluckInterval = 60.0 / tempoBpm
        voice1.varyTempo = varyTempo
        voice2.varyTempo = varyTempo

        // Only warm the sample set that's actually about to play (mirrors
        // init()'s "prewarm the initial key first, everything else in the
        // background" strategy — the slow part is the offline pitch-shift
        // render, not the plain wav decode).
        let anchor = AnchorRoots.nearest(to: baseMidi)
        let initialKey: String
        if let altAlt = AnchorRoots.altAltKey, anchor.keys.contains(altVoice ? altAlt : (AnchorRoots.altBaseKey ?? altAlt)) {
            initialKey = altVoice ? altAlt : (AnchorRoots.altBaseKey ?? altAlt)
        } else {
            initialKey = anchor.keys.first ?? "Cs3"
        }

        do {
            try await library.prewarmSet(initialKey)
            _ = try await library.loadFallbackNi()

            voice1.preferredSetKey = initialKey
            voice2.preferredSetKey = initialKey
            try await voice1.setSampleSet(initialKey, library: library)
            try await voice2.setSampleSet(initialKey, library: library)

            if let saved {
                applyPanelSettings(saved.panels.first, to: voice1)
                applyPanelSettings(saved.panels.count > 1 ? saved.panels[1] : nil, to: voice2)
            }

            await applyTuningToVoices()
            isReady = true

            // Warm the remaining sample sets in the background; already-warmed
            // entries are cached and skipped.
            Task.detached(priority: .background) { [library] in
                try? await library.prewarmAll()
            }
        } catch {
            startupError = "Failed to load samples: \(error)"
            print("Failed to warm samples: \(error)")
        }
    }

    private func applyPanelSettings(_ panel: PanelSettings?, to voice: TanpuraVoice) {
        guard let panel else { return }
        voice.volume = panel.volume
        voice.pan = panel.pan
        if let secondNoteRaw = panel.secondNote, let note = StringName(rawValue: secondNoteRaw) {
            voice.secondNote = note
            if panel.playing {
                voice.start()
            }
        }
    }

    // MARK: - Key / tuning controls

    func raiseKey() {
        guard canRaiseKey else { return }
        baseMidi += 1
        Task { await applyTuningToVoices() }
        save()
    }

    func lowerKey() {
        guard canLowerKey else { return }
        baseMidi -= 1
        Task { await applyTuningToVoices() }
        save()
    }

    func setFineCents(_ cents: Double) {
        fineCents = cents
        Task { await applyTuningToVoices() }
        save()
    }

    /// Decides which sample set should be sounding for the current key on
    /// each voice (auto register switch), applies it if it changed, then
    /// applies the semitone/cents tuning. Mirrors applyTuningToVoices().
    func applyTuningToVoices() async {
        for voice in [voice1, voice2] {
            let anchor = AnchorRoots.nearest(to: baseMidi)
            let desiredKey = anchor.keys.contains(voice.preferredSetKey) ? voice.preferredSetKey : (anchor.keys.first ?? voice.preferredSetKey)

            if await voice.currentSetKeyIsDifferent(from: desiredKey) {
                try? await voice.setSampleSet(desiredKey, library: library)
            }

            let shift = Double(baseMidi - anchor.midi)
            voice.setTuning(semitoneShift: shift, cents: fineCents)
            voice.activeSampleLabelUpdate(anchorRoot: anchor.root)
        }
    }

    private func handleAltVoiceChange() async {
        guard let baseKey = AnchorRoots.altBaseKey, let altKey = AnchorRoots.altAltKey else { return }
        let key = altVoice ? altKey : baseKey
        voice1.preferredSetKey = key
        voice2.preferredSetKey = key
        await applyTuningToVoices()
        save()
    }

    // MARK: - Persistence

    func save() {
        let settings = AppSettings(
            baseMidi: baseMidi,
            fineCents: fineCents,
            tempoBpm: tempoBpm,
            varyTempo: varyTempo,
            altVoice: altVoice,
            panels: [voice1, voice2].map {
                PanelSettings(volume: $0.volume, pan: $0.pan, secondNote: $0.secondNote?.rawValue, playing: $0.isPlaying)
            }
        )
        SettingsStore.save(settings)
    }
}
