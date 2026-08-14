import Foundation

/// Mirrors app.js's NOTE_NAMES / noteToMidi / midiToNote.
enum Note {
    static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// "C#3" -> MIDI number.
    static func toMidi(_ note: String) -> Int {
        // Split trailing signed integer octave from the leading note name.
        var idx = note.endIndex
        while idx > note.startIndex {
            let prev = note.index(before: idx)
            if note[prev].isNumber || note[prev] == "-" {
                idx = prev
            } else {
                break
            }
        }
        let name = String(note[note.startIndex..<idx])
        let octave = Int(note[idx...]) ?? 3
        let pitchClass = names.firstIndex(of: name) ?? 0
        return pitchClass + (octave + 1) * 12
    }

    struct Parsed {
        let name: String
        let octave: Int
        var label: String { "\(name)\(octave)" }
    }

    static func fromMidi(_ midi: Int) -> Parsed {
        let name = names[((midi % 12) + 12) % 12]
        let octave = Int(floor(Double(midi) / 12.0)) - 1
        return Parsed(name: name, octave: octave)
    }
}
