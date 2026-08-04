import SwiftUI

struct PlaybackCDNRouteSettingsView: View {
    @Binding var selection: PlaybackCDNRoute
    @Binding var testValidity: CDNConnectivityTestValidity
    @State private var results: [PlaybackCDNRoute: PlaybackCDNProbeResult] = [:]
    @State private var probeTask: Task<Void, Never>?
    @State private var autoTestRecord: PlaybackCDNAutoTestRecord?

    private var isProbing: Bool { probeTask != nil }

    private var routes: [PlaybackCDNRoute] {
        let fixed: [PlaybackCDNRoute] = [.automatic, .original, .backup]
        let manual = PlaybackCDNRoute.manualRoutes.sorted { lhs, rhs in
            guard let left = results[lhs], let right = results[rhs] else {
                return results[lhs] != nil
            }
            if left.didSucceed != right.didSucceed { return left.didSucceed }
            switch (left.elapsedMilliseconds, right.elapsedMilliseconds) {
            case let (a?, b?): return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.title < rhs.title
            }
        }
        return fixed + manual
    }

    var body: some View {
        List {
            Section {
                ForEach(routes) { route in
                    Button {
                        selection = route
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(route.title)
                                    .foregroundStyle(.primary)
                                if let host = route.host {
                                    Text(host)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if route == .automatic {
                                    Text(autoRouteDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 5) {
                                if let result = results[route] {
                                    Text(result.statusText)
                                        .font(.caption)
                                        .multilineTextAlignment(.trailing)
                                        .foregroundStyle(resultColor(for: result))
                                }
                                if selection == route {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color("BiliPink"))
                                }
                            }
                        }
                    }
                    .tint(.primary)
                }
            } header: {
                Text("CDN 线路")
            } footer: {
                Text("CDN 线路选择只会覆写媒体播放 URL 的 Host。")
            }

            Section {
                NavigationLink {
                    ChoiceListView(
                        title: "测试间隔",
                        options: CDNConnectivityTestValidity.allCases,
                        selection: $testValidity,
                        titleFor: \.title
                    )
                } label: {
                    HStack {
                        Text("测试间隔")
                        Spacer()
                        Text(testValidity.title)
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    PlaybackCDNAutoTestRecordView(record: $autoTestRecord)
                } label: {
                    Text("自动测试记录")
                }
            } header: {
                Text("自动测试")
            }

            Section {
                Button {
                    if isProbing {
                        probeTask?.cancel()
                        probeTask = nil
                    } else {
                        startProbe()
                    }
                } label: {
                    HStack {
                        if isProbing { ProgressView().padding(.trailing, 4) }
                        Text(isProbing ? "取消测速" : "测速")
                    }
                }
            } footer: {
                Text(PlaybackCDNProbeURLStore.shared.currentURLs().isEmpty
                    ? "当前没有可用的真实播放 URL，将使用 Host 连通性参考请求，403/959 仅代表 CDN 拒绝裸探测，不代表播放失败。"
                    : "将使用当前已拿到的真实播放 URL（保留原路径和签名）进行并行测速。")
            }
        }
        .navigationTitle("CDN 线路")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            probeTask?.cancel()
            probeTask = nil
        }
        .onAppear {
            autoTestRecord = PlaybackCDNAutoTestStore.load()
        }
    }

    private func startProbe() {
        guard probeTask == nil else { return }
        let playbackURLs = PlaybackCDNProbeURLStore.shared.currentURLs()
        probeTask = Task {
            let probeResults = await PlaybackCDNProbeService.probeAll(playbackURLs: playbackURLs)
            guard !Task.isCancelled else { return }
            results = Dictionary(uniqueKeysWithValues: probeResults.map { ($0.route, $0) })
            probeTask = nil
        }
    }

    private func resultColor(for result: PlaybackCDNProbeResult) -> Color {
        if result.didSucceed { return result.isWeakReference ? .yellow : .green }
        if result.isWeakReference, result.httpStatusCode == 403 || result.httpStatusCode == 959 { return .yellow }
        if result.httpStatusCode != nil { return .yellow }
        return .red
    }

    private var autoRouteDescription: String {
        guard let record = autoTestRecord else { return "暂无测速结果，将使用主要 URL" }
        if record.selectedRoute == .original { return "上次测试无可用 CDN，使用主要 URL" }
        return "上次测试选择：\(record.selectedRoute.title)"
    }
}

private struct PlaybackCDNAutoTestRecordView: View {
    @Binding var record: PlaybackCDNAutoTestRecord?

    var body: some View {
        List {
            if let record {
                Section {
                    LabeledContent("测试时间") {
                        Text(record.testedAt, format: .dateTime.year().month().day().hour().minute().second())
                    }
                    LabeledContent("最终选择") {
                        Text(record.selectedRoute.title)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("测试视频 URL")
                        Text(record.primaryURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text("在清除记录后，下次播放视频会重新测试最优线路。")
                }

                Section("各线路响应") {
                    ForEach(record.results) { result in
                        HStack {
                            Text(result.route.title)
                            Spacer()
                            Text(result.statusText)
                                .font(.caption)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(resultColor(for: result))
                        }
                    }
                }
            } else {
                ContentUnavailableView("暂无自动测试记录", systemImage: "clock")
            }
        }
        .navigationTitle("自动测试记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清除记录", role: .destructive) {
                    PlaybackCDNAutoTestStore.clear()
                    PlaybackCDNAutoTestCoordinator.shared.resetFirstVideoGate()
                    record = nil
                }
                .disabled(record == nil)
            }
        }
    }

    private func resultColor(for result: PlaybackCDNProbeResult) -> Color {
        if result.didSucceed { return result.isWeakReference ? .yellow : .green }
        if result.isWeakReference, result.httpStatusCode == 403 || result.httpStatusCode == 959 { return .yellow }
        if result.httpStatusCode != nil { return .yellow }
        return .red
    }
}
