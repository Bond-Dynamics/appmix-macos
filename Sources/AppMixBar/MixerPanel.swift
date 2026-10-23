import SwiftUI

struct MixerPanel: View {
    private static let width: CGFloat = 360

    let model: MixerViewModel
    let loginItem: LoginItemModel
    let updater: UpdaterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.rows.isEmpty {
                Text(model.showIdleApps ? "No apps are using audio." : "No apps are playing audio.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                ForEach(model.rows) { AppRowView(row: $0, model: model) }
            }
            Divider()
            DeviceSectionView(model: model)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: Self.width)
        .onAppear {
            model.startMeters()
            loginItem.refresh()
        }
        .onDisappear { model.stopMeters() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("AppMix").font(.headline)
            Spacer()
            Text("Default output: \(model.defaultOutputName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apps play normally until you change them. Changes are remembered.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Show apps that aren't playing", isOn: Binding(get: { model.showIdleApps }, set: { model.setShowIdleApps($0) }))
                .toggleStyle(.checkbox)
            loginItemControls
            if updater.isAvailable {
                Toggle(
                    "Check for updates automatically",
                    isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.setAutomaticallyChecks($0) })
                )
                .toggleStyle(.checkbox)
            }
            HStack {
                Button("Audio permission…") { model.openPermissionSettings() }
                    .buttonStyle(.link)
                    .font(.caption)
                Spacer()
                if updater.isAvailable {
                    updateButton
                }
                Button("Quit AppMix") { model.quit() }
                    .controlSize(.small)
            }
        }
    }

    private var updateButton: some View {
        Button(updater.pendingVersion.map { "Update to \($0)…" } ?? "Check for Updates…") { updater.checkForUpdates() }
            .buttonStyle(.link)
            .disabled(!updater.canCheck)
            .font(updater.pendingVersion == nil ? .caption : .caption.weight(.semibold))
    }

    @ViewBuilder
    private var loginItemControls: some View {
        Toggle("Launch at login", isOn: Binding(get: { loginItem.isOn }, set: { loginItem.setEnabled($0) }))
            .toggleStyle(.checkbox)
        if loginItem.state == .needsApproval {
            Button("Allow AppMix in Login Items…") { loginItem.openLoginItemsSettings() }
                .buttonStyle(.link)
                .font(.caption)
        }
        if let error = loginItem.error {
            Text(error).font(.caption2).foregroundStyle(.red).lineLimit(3)
        }
    }
}
