import SwiftUI

struct RootView: View {
    @EnvironmentObject private var configStore: ConfigStore

    var body: some View {
        Group {
            if configStore.config.isConfigured {
                ChannelView(configStore: configStore)
            } else {
                SetupView()
            }
        }
        .preferredColorScheme(.dark)
    }
}
