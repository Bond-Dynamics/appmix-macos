import MixerCore
import SwiftUI

/// Each output device's own volume and mute. macOS only puts the default output on the volume keys,
/// so this is the one place to fix a quiet or muted device an app was sent to.
struct DeviceSectionView: View {
    @AppStorage("showOutputDevices") private var isExpanded = true

    let model: MixerViewModel

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.deviceRows) { DeviceRowView(row: $0, model: model) }
            }
            .padding(.top, 4)
        } label: {
            Text("Output devices").font(.subheadline.weight(.semibold))
        }
    }
}

private struct DeviceRowView: View {
    private static let nameWidth: CGFloat = 118

    let row: DeviceVolumeRow
    let model: MixerViewModel

    private var volume: DeviceVolume { row.volume }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                muteButton
                name
                Slider(
                    value: Binding(get: { volume.percent ?? 0 }, set: { model.setDeviceVolume($0, for: row.uid) }),
                    in: 0...100,
                    onEditingChanged: { model.setDeviceEditing($0, for: row.uid) }
                )
                .controlSize(.small)
                .disabled(!volume.canSetVolume || volume.isMuted == true)
                percent
            }
            .help(volume.canSetVolume ? row.name : "\(row.name) has a fixed volume. Use the device's own controls.")
            if let error = row.error {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2).padding(.leading, 26)
            }
        }
    }

    private var muteButton: some View {
        Button { model.setDeviceMuted(volume.isMuted != true, for: row.uid) } label: {
            Image(systemName: volume.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .frame(width: 18)
        }
        .buttonStyle(.borderless)
        .disabled(!volume.canSetMute)
        .help(volume.isMuted == true ? "Unmute \(row.name)" : "Mute \(row.name)")
    }

    private var name: some View {
        HStack(spacing: 4) {
            Text(row.name).lineLimit(1).truncationMode(.tail)
            if row.isDefault {
                Text("default").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .frame(width: Self.nameWidth, alignment: .leading)
    }

    private var percent: some View {
        Text(volume.percent.map { "\(Int($0.rounded()))%" } ?? "Fixed")
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(volume.canSetVolume ? .primary : .secondary)
            .frame(width: 38, alignment: .trailing)
    }
}
