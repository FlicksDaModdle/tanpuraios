import AVFoundation

// AVFoundation predates Swift concurrency, so AVAudioPCMBuffer isn't marked
// Sendable even though our usage pattern is safe: SampleLibrary (an actor)
// creates buffers once, caches them, and hands out the *same* buffer to
// every caller — we never mutate a buffer's contents after it's created, we
// only read from it (scheduling it for playback, feeding it to
// AVAudioUnitTimePitch for pitch-shifting). That makes concurrent reads from
// multiple isolation domains safe in practice, so this retroactive
// conformance is a correct assertion, not a workaround for a real bug.
extension AVAudioPCMBuffer: @unchecked @retroactive Sendable {}
