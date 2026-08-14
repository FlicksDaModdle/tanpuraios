import AVFoundation

/// One playable note source: a buffer plus any extra semitone offset needed
/// on top of the voice's global tuning (mirrors app.js's noteSources map,
/// where e.g. Ma is really "the derived buffer, extraSemitones: 0" since the
/// pitch shift was already baked in when the buffer was derived).
struct NoteSource {
    let buffer: AVAudioPCMBuffer
    let extraSemitones: Double
}

/// How long each pluck's attack is faded in, softening the recorded strike
/// transient — matches PLUCK_ATTACK_TIME in app.js.
private let pluckAttackTime: TimeInterval = 0.035

/// Traditional 6-beat plucking cycle, identical to buildSequence() in app.js:
///   1: second string (Pa/Ma/Ni) · 2: rest · 3: Sa (held through beat 4)
///   4: rest · 5: Kharaj · 6: rest
private func buildSequence(secondNote: StringName?) -> [StringName?] {
    if let secondNote { return [secondNote, nil, .sa, nil, .kharaj, nil] }
    return [nil, nil, .sa, nil, .kharaj, nil]
}

@MainActor
final class TanpuraVoice: ObservableObject {
    let id: Int
    private let engine: AVAudioEngine
    private let mixerGain: AVAudioMixerNode
    private let panMixer: AVAudioMixerNode

    // Active per-pluck node chains, so tuning changes can retarget them live.
    private struct ActiveSource {
        let player: AVAudioPlayerNode
        let varispeed: AVAudioUnitVarispeed
        let extraFactor: Double
    }
    private var activeSources: [ActiveSource] = []

    @Published var volume: Double = 0.8 {
        didSet { panMixer.outputVolume = Float(volume) }
    }
    @Published var pan: Double = 0 {
        didSet { panMixer.pan = Float(pan) }
    }
    @Published private(set) var setKey: String = "Cs3"
    @Published var secondNote: StringName? = nil
    @Published private(set) var isPlaying = false
    @Published private(set) var activeSampleLabel: String = ""

    /// Which sample-set variant the user *prefers* (Cs3 vs Cs3Alt), independent
    /// of which set is actually sounding — see TanpuraEngine.applyTuning().
    var preferredSetKey: String = "Cs3"

    private var noteSources: [StringName: NoteSource] = [:]
    private var globalSemitoneShift: Double = 0
    private var globalCents: Double = 0

    var pluckInterval: TimeInterval = 60.0 / 105.0
    var varyTempo: Bool = true

    private var running = false
    private var nextPluckTime: AVAudioTime?
    private var seqIndex = 0
    private let lookahead: TimeInterval = 0.5
    private var schedulerTimer: DispatchSourceTimer?

    /// UI callback for the string-pluck pulse animation.
    var onPluck: ((StringName) -> Void)?

    init(id: Int, engine: AVAudioEngine, destination: AVAudioNode) {
        self.id = id
        self.engine = engine
        self.mixerGain = AVAudioMixerNode()
        self.panMixer = AVAudioMixerNode()
        engine.attach(mixerGain)
        engine.attach(panMixer)
        engine.connect(mixerGain, to: panMixer, format: nil)
        engine.connect(panMixer, to: destination, format: nil)
        panMixer.outputVolume = Float(volume)
        panMixer.pan = Float(pan)
    }

    func setSampleSet(_ key: String, library: SampleLibrary) async throws {
        guard let set = SampleSets.all[key] else { return }
        let buffers = try await library.loadSet(key)

        var sources: [StringName: NoteSource] = [:]
        if let kharaj = buffers[.kharaj] { sources[.kharaj] = NoteSource(buffer: kharaj, extraSemitones: 0) }
        if let sa = buffers[.sa] { sources[.sa] = NoteSource(buffer: sa, extraSemitones: 0) }

        var paBuffer = buffers[.pa]
        var paName = set.files[.pa]

        if paBuffer == nil, let deriveSpec = set.derivePa, let sourceSet = SampleSets.all[deriveSpec.fromSet] {
            let sourcePaName = sourceSet.files[.pa]!
            let sourcePa = try await library.load(sourcePaName)
            paBuffer = try await library.getPitchShifted(sourceName: sourcePaName, source: sourcePa, semitones: deriveSpec.semitones)
            paName = "\(sourcePaName)#derived-\(key)"
        }

        if let paBuffer, let paName {
            sources[.pa] = NoteSource(buffer: paBuffer, extraSemitones: 0)
            let maBuffer = try await library.getPitchShifted(sourceName: paName, source: paBuffer, semitones: -2)
            // "ma" isn't a StringName case (only kharaj/sa/pa/ni are recorded
            // string names); we key it separately below via availableSecondNotes.
            sources[.ma] = NoteSource(buffer: maBuffer, extraSemitones: 0)
        }

        if let ni = buffers[.ni] {
            sources[.ni] = NoteSource(buffer: ni, extraSemitones: 0)
        } else {
            sources[.ni] = NoteSource(buffer: try await library.loadFallbackNi(), extraSemitones: 0)
        }

        self.noteSources = sources
        self.setKey = key

        if let current = secondNote, sources[current] == nil {
            secondNote = availableSecondNotes().first
        }
    }

    func currentSetKeyIsDifferent(from key: String) -> Bool {
        setKey != key
    }

    /// Mirrors updateActiveSampleReadout(): shows which set is actually
    /// sounding, flagged "auto →" when it differs from the user's preference.
    func activeSampleLabelUpdate(anchorRoot: String) {
        let registerLabel = anchorRoot == "G#3" ? "female register" : "male register"
        let setLabel = SampleSets.all[setKey]?.label ?? setKey
        let isAuto = setKey != preferredSetKey
        activeSampleLabel = isAuto ? "auto → \(setLabel) · \(registerLabel)" : "\(setLabel) · \(registerLabel)"
    }

    func availableSecondNotes() -> [StringName] {
        StringName.allCases.filter { $0 != .kharaj && $0 != .sa && noteSources[$0] != nil }
    }

    func setTuning(semitoneShift: Double, cents: Double) {
        globalSemitoneShift = semitoneShift
        globalCents = cents
        let rate = playbackRateMultiplier()
        // Re-target every currently-ringing string immediately, mirroring
        // app.js's cancel-and-ramp behaviour on the AudioParam. AVAudioUnitVarispeed's
        // rate isn't a scheduleable AUParameter ramp like Web Audio's, so we
        // set it directly — the change is inaudible-click because the pluck's
        // gain envelope is already past its attack by the time a slider moves.
        for active in activeSources {
            active.varispeed.rate = Float(rate * active.extraFactor)
        }
    }

    private func playbackRateMultiplier() -> Double {
        let semitoneFactor = pow(2.0, globalSemitoneShift / 12.0)
        let centsFactor = pow(2.0, globalCents / 1200.0)
        return semitoneFactor * centsFactor
    }

    private func pluck(_ note: StringName, at time: AVAudioTime) {
        guard let source = noteSources[note] else { return }
        let player = AVAudioPlayerNode()
        let varispeed = AVAudioUnitVarispeed()
        let extraFactor = pow(2.0, source.extraSemitones / 12.0)
        varispeed.rate = Float(playbackRateMultiplier() * extraFactor)

        engine.attach(player)
        engine.attach(varispeed)
        engine.connect(player, to: varispeed, format: source.buffer.format)
        engine.connect(varispeed, to: mixerGain, format: source.buffer.format)

        player.volume = 0 // start silent; ramp in via a short fade to soften the strike transient
        player.scheduleBuffer(source.buffer, at: time, options: []) { [weak self, weak player] in
            guard let self, let player else { return }
            Task { @MainActor in
                self.engine.disconnectNodeOutput(player)
                self.engine.detach(player)
                self.engine.detach(varispeed)
                self.activeSources.removeAll { $0.player === player }
            }
        }
        player.play(at: time)
        rampInVolume(player: player)

        activeSources.append(ActiveSource(player: player, varispeed: varispeed, extraFactor: extraFactor))

        let delay = max(0, time.hostTimeStamp(sinceNow: engine))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.onPluck?(note)
        }
    }

    /// Softens the recorded strike transient with a short fade-in, matching
    /// app.js's per-pluck gain envelope (0 -> 1 over PLUCK_ATTACK_TIME).
    private func rampInVolume(player: AVAudioPlayerNode) {
        let steps = 8
        let stepDuration = pluckAttackTime / Double(steps)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) {
                player.volume = Float(t)
            }
        }
    }

    func start() {
        guard !running, !noteSources.isEmpty else { return }
        running = true
        isPlaying = true
        seqIndex = 0
        nextPluckTime = nil
        scheduleLoop()
    }

    func stop() {
        running = false
        isPlaying = false
        schedulerTimer?.cancel()
        schedulerTimer = nil
        // Let currently-sounding plucks ring out naturally; only stop scheduling new ones.
    }

    private func scheduleLoop() {
        schedulerTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 0.025)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        schedulerTimer = timer
        timer.resume()
    }

    private func tick() {
        guard running else { return }
        let sequence = buildSequence(secondNote: secondNote.flatMap { noteSources[$0] != nil ? $0 : nil })

        let now = engine.outputNode.lastRenderTime.map { AVAudioTime(hostTime: $0.hostTime) } ?? AVAudioTime(hostTime: mach_absolute_time())
        if nextPluckTime == nil {
            nextPluckTime = now
        }

        while let next = nextPluckTime, next.timeIntervalSinceNow(engine: engine) < lookahead {
            let note = sequence[seqIndex % sequence.count]
            if let note {
                pluck(note, at: next)
            }
            let jitter = varyTempo ? 1 + (Double.random(in: -1...1) * 0.045) : 1
            nextPluckTime = next.offset(seconds: pluckInterval * jitter)
            seqIndex += 1
        }
    }
}

// MARK: - AVAudioTime helpers

private extension AVAudioTime {
    /// Approximate seconds from "now" to this time, using host ticks.
    func timeIntervalSinceNow(engine: AVAudioEngine) -> TimeInterval {
        let nowHost = mach_absolute_time()
        let diff = Int64(hostTime) - Int64(nowHost)
        return AVAudioTime.seconds(forHostTime: UInt64(max(0, diff)))
    }

    func hostTimeStamp(sinceNow engine: AVAudioEngine) -> TimeInterval {
        timeIntervalSinceNow(engine: engine)
    }

    func offset(seconds: TimeInterval) -> AVAudioTime {
        let ticks = AVAudioTime.hostTime(forSeconds: seconds)
        return AVAudioTime(hostTime: hostTime + ticks)
    }
}
