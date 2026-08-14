import AVFoundation

/// Loads recorded samples and derives pitch-shifted, duration-preserving
/// variants (used to synthesize Ma from a Pa recording, and to synthesize
/// G#3's missing Pa from C#3's real Pa recording).
///
/// app.js does this itself with a hand-rolled resample + WSOLA time-stretch
/// because Web Audio has no built-in duration-preserving pitch shifter.
/// AVFoundation gives us that for free: AVAudioUnitTimePitch shifts pitch
/// (in cents) while holding duration fixed, using the same phase-vocoder-
/// style approach WSOLA approximates by hand. We render it once offline per
/// (source, semitones) pair via a manual-rendering AVAudioEngine and cache
/// the result, exactly mirroring SampleLibrary's derivedCache in app.js.
actor SampleLibrary {
    private var bufferCache: [String: AVAudioPCMBuffer] = [:]
    private var derivedCache: [String: AVAudioPCMBuffer] = [:]
    private var fallbackNiBuffer: AVAudioPCMBuffer?

    /// Loads (or returns cached) the raw recorded buffer for a resource name.
    func load(_ resourceName: String) throws -> AVAudioPCMBuffer {
        if let cached = bufferCache[resourceName] { return cached }
        // Depending on how the resource got bundled (flattened vs. preserved
        // as a folder reference), the wav can end up either at the bundle
        // root or nested under "Audio/" — check both rather than guessing.
        let url = Bundle.main.url(forResource: resourceName, withExtension: "wav")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "wav", subdirectory: "Audio")
        guard let url else {
            throw SampleLibraryError.missingResource(resourceName)
        }
        let file = try AVAudioFile(forReading: url)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.fileFormat.sampleRate,
            channels: file.fileFormat.channelCount,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SampleLibraryError.decodeFailed(resourceName)
        }
        try file.read(into: buffer)
        bufferCache[resourceName] = buffer
        return buffer
    }

    /// Every sample set falls back to C#3's Ni recording when it wasn't
    /// recorded with its own — same as app.js's loadFallbackNi().
    func loadFallbackNi() throws -> AVAudioPCMBuffer {
        if let cached = fallbackNiBuffer { return cached }
        let buf = try load(SampleSets.all["Cs3"]!.files[.ni]!)
        fallbackNiBuffer = buf
        return buf
    }

    /// Derives a pitch-shifted, duration-preserving buffer, cached per
    /// (source resource name, semitone shift). Mirrors getPitchShifted().
    func getPitchShifted(sourceName: String, source: AVAudioPCMBuffer, semitones: Double) throws -> AVAudioPCMBuffer {
        let cacheKey = "\(sourceName)::\(semitones)"
        if let cached = derivedCache[cacheKey] { return cached }
        let shifted = try Self.renderPitchShift(source: source, semitones: semitones)
        derivedCache[cacheKey] = shifted
        return shifted
    }

    /// Loads every recorded string in a sample set. Mirrors loadSet().
    func loadSet(_ key: String) throws -> [StringName: AVAudioPCMBuffer] {
        guard let set = SampleSets.all[key] else { throw SampleLibraryError.missingResource(key) }
        var out: [StringName: AVAudioPCMBuffer] = [:]
        for (name, resource) in set.files {
            out[name] = try load(resource)
        }
        return out
    }

    /// Loads + pre-derives everything a set needs to play (Ma from Pa, or a
    /// derived Pa+Ma for G#3), so a later register/alt switch is just a
    /// cache hit with no audible stall. Mirrors prewarmSet().
    func prewarmSet(_ key: String) throws {
        guard let set = SampleSets.all[key] else { return }
        let buffers = try loadSet(key)
        if let pa = buffers[.pa] {
            _ = try getPitchShifted(sourceName: set.files[.pa]!, source: pa, semitones: -2)
        } else if let deriveSpec = set.derivePa, let sourceSet = SampleSets.all[deriveSpec.fromSet] {
            let sourcePaName = sourceSet.files[.pa]!
            let sourcePa = try load(sourcePaName)
            let derivedPa = try getPitchShifted(sourceName: sourcePaName, source: sourcePa, semitones: deriveSpec.semitones)
            _ = try getPitchShifted(sourceName: "\(sourcePaName)#derived-\(key)", source: derivedPa, semitones: -2)
        }
    }

    func prewarmAll() throws {
        for key in SampleSets.order {
            try prewarmSet(key)
        }
        _ = try loadFallbackNi()
    }

    // MARK: - Offline pitch shift rendering

    private static func renderPitchShift(source: AVAudioPCMBuffer, semitones: Double) throws -> AVAudioPCMBuffer {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.pitch = Float(semitones * 100) // AVAudioUnitTimePitch takes cents
        timePitch.rate = 1.0 // duration-preserving: only pitch moves, not speed

        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: source.format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: source.format)

        try engine.enableManualRenderingMode(.offline, format: source.format, maximumFrameCount: 4096)
        try engine.start()
        player.play()
        player.scheduleBuffer(source, at: nil, options: .interrupts)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else {
            throw SampleLibraryError.renderFailed
        }

        let outputFile = try makeAccumulator(format: source.format, estimatedFrames: source.frameLength)
        var framesRemaining = Int64(source.frameLength) + Int64(source.format.sampleRate) // small tail for reverb/decay of the time-pitch unit
        while framesRemaining > 0 {
            let framesToRender = min(AVAudioFrameCount(framesRemaining), engine.manualRenderingMaximumFrameCount)
            let status = try engine.renderOffline(framesToRender, to: outputBuffer)
            switch status {
            case .success:
                outputFile.append(outputBuffer)
                framesRemaining -= Int64(outputBuffer.frameLength)
            case .insufficientDataFromInputNode:
                continue
            case .cannotDoInCurrentContext:
                continue
            case .error:
                throw SampleLibraryError.renderFailed
            @unknown default:
                throw SampleLibraryError.renderFailed
            }
        }
        engine.stop()
        return outputFile.buffer(trimmedTo: source.frameLength)
    }

    /// Small helper that accumulates rendered chunks into one growable buffer.
    private static func makeAccumulator(format: AVAudioFormat, estimatedFrames: AVAudioFrameCount) throws -> PCMAccumulator {
        PCMAccumulator(format: format, estimatedFrames: estimatedFrames)
    }
}

enum SampleLibraryError: Error {
    case missingResource(String)
    case decodeFailed(String)
    case renderFailed
}

/// Accumulates AVAudioPCMBuffer chunks from offline rendering into a single
/// contiguous buffer, then trims to the target length (matching the source
/// recording's original duration, same intent as app.js's padOrTrim()).
private final class PCMAccumulator {
    private var storage: [[Float]]
    private let format: AVAudioFormat
    private var frameCount: AVAudioFrameCount = 0

    init(format: AVAudioFormat, estimatedFrames: AVAudioFrameCount) {
        self.format = format
        self.storage = (0..<Int(format.channelCount)).map { _ in
            [Float](repeating: 0, count: Int(estimatedFrames) + Int(format.sampleRate) * 2)
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let framesToAppend = Int(buffer.frameLength)
        let neededCapacity = Int(frameCount) + framesToAppend
        for ch in 0..<storage.count {
            if storage[ch].count < neededCapacity {
                storage[ch].append(contentsOf: [Float](repeating: 0, count: neededCapacity - storage[ch].count))
            }
            let src = channelData[min(ch, Int(buffer.format.channelCount) - 1)]
            for i in 0..<framesToAppend {
                storage[ch][Int(frameCount) + i] = src[i]
            }
        }
        frameCount += AVAudioFrameCount(framesToAppend)
    }

    func buffer(trimmedTo length: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let finalLength = min(length, frameCount)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: finalLength) else {
            fatalError("Failed to allocate trimmed buffer")
        }
        out.frameLength = finalLength
        for ch in 0..<storage.count {
            guard let dst = out.floatChannelData?[ch] else { continue }
            for i in 0..<Int(finalLength) {
                dst[i] = storage[ch][i]
            }
        }
        return out
    }
}
