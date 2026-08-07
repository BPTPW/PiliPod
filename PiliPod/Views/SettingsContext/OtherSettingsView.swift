import SwiftUI

struct OtherSettingsView: View {
    @State private var settings = SponsorBlockSettingsStore.load()

    var body: some View {
        Form {
            Section {
                Toggle("空降助手", isOn: $settings.isEnabled)
                    .tint(Color("BiliPink"))

                NavigationLink {
                    SponsorBlockSettingsContainerView()
                } label: {
                    HStack {
                        Text("空降助手设置")
                    }
                }
            }
        }
        .navigationTitle("其他设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            settings = SponsorBlockSettingsStore.load()
        }
        .onChange(of: settings) { _, newValue in
            var updated = newValue.clamped()
            SponsorBlockSettingsStore.ensureUserIDIfNeeded(for: &updated)
            settings = updated
            SponsorBlockSettingsStore.save(updated)
        }
    }
}
