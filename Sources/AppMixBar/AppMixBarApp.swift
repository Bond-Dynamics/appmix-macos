import SwiftUI

@main
struct AppMixBarApp: App {
    @State private var model = MixerViewModel()
    @State private var loginItem = LoginItemModel()

    var body: some Scene {
        MenuBarExtra("AppMix", systemImage: "slider.vertical.3") {
            MixerPanel(model: model, loginItem: loginItem)
        }
        .menuBarExtraStyle(.window)
    }
}
