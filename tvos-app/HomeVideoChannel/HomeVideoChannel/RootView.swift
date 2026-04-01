import SwiftUI

struct RootView: View {
    @EnvironmentObject private var configStore: ConfigStore
    @StateObject private var whatsNewController = WhatsNewController()

    var body: some View {
        Group {
            if configStore.config.isConfigured {
                ChannelView(configStore: configStore)
            } else {
                SetupView()
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: whatsNewBinding) { entry in
            WhatsNewView(entry: entry) {
                whatsNewController.acknowledgeCurrentEntry()
            }
        }
    }

    private var whatsNewBinding: Binding<WhatsNewEntry?> {
        Binding(
            get: { whatsNewController.presentedEntry },
            set: { nextValue in
                if nextValue == nil {
                    whatsNewController.acknowledgeCurrentEntry()
                }
            }
        )
    }
}
