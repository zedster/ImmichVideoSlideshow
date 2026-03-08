import SwiftUI

@main
struct ImmichChannelTVApp: App {
    @StateObject private var configStore = ConfigStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(configStore)
        }
    }
}
