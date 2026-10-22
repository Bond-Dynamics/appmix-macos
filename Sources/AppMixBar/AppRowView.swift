import MixerCore
import SwiftUI

struct AppRowView: View {
    let row: AppRowModel
    let model: MixerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleLine
            volumeLine
            if row.isRouted {
                LevelMeter(peak: model.levels[row.id] ?? 0)
            }
            if let error = row.error {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2)
            }
        }
    }

    private var titleLine: some View {
        HStack(spacing: 8) {
            Image(nsImage: model.icon(for: row))
            Text(row.name).lineLimit(1).truncationMode(.tail)
            if !row.isPlaying {
                Text("paused").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            outputPicker
            if row.settings.needsTap {
                Button { model.reset(row.id) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless)
                    .help("Reset: play this app normally again")
            }
        }
    }

    private var volumeLine: some View {
        HStack(spacing: 8) {
            Button { model.setMuted(!row.settings.isMuted, for: row.id) } label: {
                Image(systemName: row.settings.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help(row.settings.isMuted ? "Unmute" : "Mute")

            Slider(
                value: Binding(get: { row.settings.volumePercent }, set: { model.setVolume($0, for: row.id) }),
                in: 0...100
            )
            .disabled(row.settings.isMuted)

            Text("\(Int(row.settings.volumePercent.rounded()))%")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
        }
    }

    private var outputPicker: some View {
        Picker("Output", selection: Binding(get: { row.settings.outputUID }, set: { model.setOutput($0, for: row.id) })) {
            Text("Default output").tag(String?.none)
            Divider()
            ForEach(model.devices, id: \.uid) { Text($0.name).tag(Optional($0.uid)) }
            if let chosen = row.settings.outputUID, !model.devices.contains(where: { $0.uid == chosen }) {
                Text("Disconnected device").tag(Optional(chosen))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
    }
}

/// Thin bar showing a routed app's output level on a -60…0 dBFS scale.
struct LevelMeter: View {
    private static let floorDecibels: Float = -60

    let peak: Float

    private var fill: CGFloat {
        let decibels = max(SampleMixing.decibels(peak), Self.floorDecibels)
        return CGFloat(1 - decibels / Self.floorDecibels)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.green.gradient).frame(width: geometry.size.width * fill)
            }
        }
        .frame(height: 4)
        .padding(.leading, 26)
        .animation(.linear(duration: 0.1), value: peak)
    }
}
