import SwiftUI

@main
struct ImmichVideoChannelApp: App {
    @StateObject private var configStore = ConfigStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(configStore)
        }
    }
}


