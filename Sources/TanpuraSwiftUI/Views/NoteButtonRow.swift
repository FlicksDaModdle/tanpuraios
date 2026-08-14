import SwiftUI

struct NoteButtonRow: View {
    @ObservedObject var voice: TanpuraVoice

    private let labels: [StringName: String] = [.pa: "Pa", .ma: "Ma", .ni: "Ni"]

    var body: some View {
        HStack(spacing: 8) {
            noteButton(label: "Off", note: nil)
            ForEach(voice.availableSecondNotes(), id: \.self) { note in
                noteButton(label: labels[note] ?? note.rawValue, note: note)
            }
        }
    }

    private func noteButton(label: String, note: StringName?) -> some View {
        let isActive = (voice.isPlaying && voice.secondNote == note) || (!voice.isPlaying && note == nil && voice.secondNote == nil)
        return Button(label) {
            if let note {
                voice.secondNote = note
                if !voice.isPlaying {
                    voice.start()
                }
            } else {
                voice.stop()
            }
        }
        .buttonStyle(.glass)
        .tint(isActive ? .accentColor : .clear)
        .foregroundStyle(.white)
    }
}
