import SwiftUI

@main
struct AppMixBarApp: App {
    @State private var model = MixerViewModel()
    @State private var loginItem = LoginItemModel()
    @State private var updater = UpdaterModel()

    var body: some Scene {
        MenuBarExtra("AppMix", systemImage: "slider.vertical.3") {
            MixerPanel(model: model, loginItem: loginItem, updater: updater)
        }
        .menuBarExtraStyle(.window)
    }
}
