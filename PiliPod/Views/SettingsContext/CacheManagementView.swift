import SwiftUI

struct CacheManagementView: View {
    @State private var summary = CacheStorageSummary.empty
    @State private var isLoading = false
    @State private var isClearing = false
    @State private var actionMessage: String?
    @State private var showClearCacheConfirmation = false

    var body: some View {
        List {
            Section {
                LabeledContent("可清理缓存总大小", value: CacheStorageService.formattedSize(summary.clearableCacheSize))
                LabeledContent("URL 响应缓存") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(CacheStorageService.formattedSize(summary.urlCacheDiskUsage))
                        Text("上限 \(CacheStorageService.formattedSize(summary.urlCacheDiskCapacity))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Library/Caches", value: CacheStorageService.formattedSize(summary.cachesDirectorySize))
                LabeledContent("tmp 临时目录", value: CacheStorageService.formattedSize(summary.temporaryDirectorySize))
            } header: {
                Text("缓存概览")
            }
            
            Section{
                LabeledContent("离线缓存视频") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(CacheStorageService.formattedSize(summary.offlineCacheSize))
                    }
                }
            } footer:{
                Text("离线缓存视频不会清理操作删除，需要管理或删除时请前往离线缓存页面。")
            }

            Section {
                Button {
                    Task {
                        await refreshSummary()
                    }
                } label: {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("正在统计缓存")
                        }
                    } else {
                        Text("刷新缓存统计")
                    }
                }
                .foregroundStyle(.primary)
                .disabled(isLoading || isClearing)

                Button(role: .destructive) {
                    showClearCacheConfirmation = true
                } label: {
                    if isClearing {
                        HStack {
                            ProgressView()
                            Text("正在清理缓存")
                        }
                    } else {
                        Text("清理缓存")
                    }
                }
                .disabled(isLoading || isClearing)
            } footer: {
                Text("会清理 URL 响应缓存、Library/Caches（保留离线缓存视频）和 tmp 临时文件。封面、头像、表情和预览图会在下次使用时重新建立缓存。")
            }
        }
        .navigationTitle("缓存管理")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .task {
            await refreshSummary()
        }
        .alert("缓存管理", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(actionMessage ?? "未知错误")
        }
        .confirmationDialog(
            "清理缓存",
            isPresented: $showClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("清理 URL 缓存与临时文件", role: .destructive) {
                Task {
                    await clearCaches()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("离线缓存视频不会被清除；如需管理，请前往离线缓存页面。页面里的封面、头像、预览图下次会重新加载。")
        }
    }

    @MainActor
    private func refreshSummary() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let value = await Task.detached(priority: .utility) {
            CacheStorageService.loadSummary()
        }.value
        summary = value
    }

    @MainActor
    private func clearCaches() async {
        guard !isClearing else { return }
        isClearing = true
        defer { isClearing = false }

        do {
            try await Task.detached(priority: .utility) {
                try CacheStorageService.clearCaches()
            }.value
            actionMessage = "缓存已清理完成。"
        } catch {
            actionMessage = error.localizedDescription
        }

        await refreshSummary()
    }
}

#Preview {
    NavigationStack {
        CacheManagementView()
    }
}
