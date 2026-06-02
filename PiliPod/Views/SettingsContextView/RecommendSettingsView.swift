import SwiftUI

struct RecommendSettingsView: View {
    @State private var selectedSource = RecommendSettingsStore.loadSource()

    var body: some View {
        Form {
            Section {
                Picker("推荐来源", selection: $selectedSource) {
                    ForEach(RecommendAPIMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } footer: {
                Text("修改会在下次首页推荐内容刷新时生效。")
            }
        }
        .navigationTitle("推荐流")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedSource = RecommendSettingsStore.loadSource()
        }
        .onChange(of: selectedSource) { _, newValue in
            RecommendSettingsStore.saveSource(newValue)
        }
    }
}

