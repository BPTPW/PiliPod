import SwiftUI

struct OfflineCacheView: View {
    let initialPrefill: OfflineCacheQueryPrefill?

    @StateObject private var cacheManager = OfflineCacheManager.shared
    @State private var isAddTaskSheetPresented = false
    @State private var bvidOrAidText = ""
    @State private var cidText = ""
    @State private var queryResult: OfflineCacheQueryResult?
    @State private var selectedQualityCode: Int?
    @State private var queryError: String?
    @State private var isQuerying = false
    @State private var hasConsumedInitialPrefill = false
    @State private var selectedVideo: VideoItem?
    @State private var isSelectionMode = false
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var itemPendingDeletion: OfflineCacheItem?
    @State private var isSingleDeleteDialogPresented = false
    @State private var isDeleteSelectionDialogPresented = false
    @State private var toastMessage: String?
    @Namespace private var videoNamespace

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if cacheManager.sortedItems.isEmpty {
                    emptyState
                } else {
                    ForEach(cacheManager.sortedItems) { item in
                        OfflineCacheCardView(
                            item: item,
                            namespace: videoNamespace,
                            isSelectionMode: isSelectionMode,
                            isSelected: selectedItemIDs.contains(item.id),
                            onTap: {
                                handleItemTap(item)
                            },
                            onDelete: {
                                itemPendingDeletion = item
                                isSingleDeleteDialogPresented = true
                            },
                            onSelect: {
                                enterSelectionMode(selecting: item.id)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("离线缓存")
        .navigationBarBackButtonHidden(isSelectionMode)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if isSelectionMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        exitSelectionMode()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("选择") {
                        isSelectionMode = true
                    }
                    .disabled(cacheManager.sortedItems.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentAddTaskSheet(prefill: nil, autoQuery: false)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isSelectionMode {
                selectionDeleteButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $isAddTaskSheetPresented) {
            addTaskSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            guard !hasConsumedInitialPrefill else { return }
            hasConsumedInitialPrefill = true
            if let initialPrefill {
                presentAddTaskSheet(prefill: initialPrefill, autoQuery: true)
            }
        }
        .navigationDestination(item: $selectedVideo) { video in
            if #available(iOS 18.0, *) {
                VideoDetailPage(video: video, namespace: videoNamespace) {
                    selectedVideo = nil
                }
                .navigationTransition(
                    .zoom(sourceID: "videoHero.\(video.bvid)", in: videoNamespace)
                )
            } else {
                VideoDetailPage(video: video, namespace: videoNamespace) {
                    selectedVideo = nil
                }
            }
        }
        .confirmationDialog(
            "删除缓存",
            isPresented: $isSingleDeleteDialogPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let itemPendingDeletion {
                    cacheManager.deleteItem(id: itemPendingDeletion.id)
                    toastMessage = "已删除缓存视频"
                }
                itemPendingDeletion = nil
            } label: {
                Label("删除", systemImage: "trash")
            }
        } message: {
            Text("这个项目将从你的设备上移除")
        }
        .toast(message: $toastMessage)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("暂无缓存视频")
                .font(.headline)

            Text("添加缓存任务或在视频播放页进行缓存")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private var selectionDeleteButton: some View {
        Button(role: .destructive) {
            isDeleteSelectionDialogPresented = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .confirmationDialog(
            "这些项目将从你的设备上移除",
            isPresented: $isDeleteSelectionDialogPresented,
            titleVisibility: .visible
        ) {
            Button("删除\(selectedItemIDs.count)个视频", role: .destructive) {
                let count = selectedItemIDs.count
                cacheManager.deleteItems(ids: selectedItemIDs)
                exitSelectionMode()
                toastMessage = "已删除\(count)个视频"
            }
        }
        .disabled(selectedItemIDs.isEmpty)
    }

    private var addTaskSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        TextField("BV号 / AV号", text: $bvidOrAidText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .glassEffect(
                                .regular.interactive(),
                                in: .capsule
                            )

                        TextField("CID (可选)", text: $cidText)
                            .keyboardType(.numberPad)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .glassEffect(
                                .regular.interactive(),
                                in: .capsule
                            )

                        Button {
                            Task { await runQuery() }
                        } label: {
                            if isQuerying {
                                ProgressView()
                                    .tint(.white)
                                    .frame(width: 40, height: 40)
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .glassEffect(
                                        .regular.interactive().tint(.blue),
                                        in: .circle
                                    )
                            }
                        }
                        .tint(.primary)
                        .disabled(isQuerying || bvidOrAidText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if let queryError, !queryError.isEmpty {
                        Text(queryError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if let queryResult {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(queryResult.detail.title)
                                .font(.headline)
                                .lineLimit(3)

                            HStack(spacing: 10) {
                                Text(queryResult.detail.owner.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HStack{
                                Text("缓存画质: ")
                                Picker(
                                    "画质",
                                    selection: Binding(
                                        get: { selectedQualityCode ?? queryResult.defaultQualityCode },
                                        set: { selectedQualityCode = $0 }
                                    )
                                ) {
                                    ForEach(queryResult.qualityOptions) { option in
                                        Text(option.label).tag(option.code)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.primary)
                            }
                            
                            Button {
                                addTask()
                            } label: {
                                Text("添加任务")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.glassProminent)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("新增缓存任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isAddTaskSheetPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }

    private func presentAddTaskSheet(prefill: OfflineCacheQueryPrefill?, autoQuery: Bool) {
        bvidOrAidText = prefill?.bvid ?? ""
        cidText = {
            guard let cid = prefill?.cid, cid > 0 else { return "" }
            return String(cid)
        }()
        queryResult = nil
        selectedQualityCode = nil
        queryError = nil
        isAddTaskSheetPresented = true

        guard autoQuery else { return }
        Task { await runQuery() }
    }

    private func handleItemTap(_ item: OfflineCacheItem) {
        if isSelectionMode {
            toggleSelection(for: item.id)
            return
        }

        switch item.status {
        case .completed:
            selectedVideo = VideoItem(
                bvid: item.bvid,
                cid: item.cid,
                cover: item.cover,
                title: item.title,
                playCount: "--",
                danmakuCount: "--",
                uploader: item.uploader,
                duration: item.duration,
                progressSeconds: nil,
                publishTimeText: "",
                bottomRcmdReasonText: nil
            )
        case .downloading, .queued:
            cacheManager.stopDownload(id: item.id)
            toastMessage = "已暂停下载"
        case .paused:
            cacheManager.restartDownload(id: item.id)
            toastMessage = "正在继续下载"
        case .failed:
            cacheManager.restartDownload(id: item.id)
            toastMessage = "正在重新下载"
        }
    }

    private func enterSelectionMode(selecting itemID: UUID? = nil) {
        isSelectionMode = true
        isDeleteSelectionDialogPresented = false
        if let itemID {
            selectedItemIDs.insert(itemID)
        }
    }

    private func toggleSelection(for itemID: UUID) {
        if selectedItemIDs.contains(itemID) {
            selectedItemIDs.remove(itemID)
        } else {
            selectedItemIDs.insert(itemID)
        }
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedItemIDs.removeAll()
        isDeleteSelectionDialogPresented = false
    }

    @MainActor
    private func runQuery() async {
        guard !isQuerying else { return }
        isQuerying = true
        defer { isQuerying = false }

        do {
            let result = try await cacheManager.queryVideo(
                bvidOrAid: bvidOrAidText,
                cid: cidText
            )
            queryResult = result
            selectedQualityCode = result.defaultQualityCode
            cidText = String(result.resolvedCID)
            queryError = nil
        } catch {
            queryResult = nil
            selectedQualityCode = nil
            queryError = error.localizedDescription
        }
    }

    private func addTask() {
        guard let queryResult else { return }
        cacheManager.addTask(
            from: queryResult,
            qualityCode: selectedQualityCode ?? queryResult.defaultQualityCode
        )
        isAddTaskSheetPresented = false
        toastMessage = "已添加缓存任务"
    }
}

private struct OfflineCacheCardView: View {
    let item: OfflineCacheItem
    let namespace: Namespace.ID
    let isSelectionMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    private let coverWidth: CGFloat = 140
    private let coverHeight: CGFloat = 88
    private let cornerRadius: CGFloat = 18
    private var heroID: String { "videoHero.\(item.bvid)" }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(url: URL(string: item.cover)) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Rectangle()
                                .fill(Color(.systemGray5))
                        }
                    }
                    .frame(width: coverWidth, height: coverHeight)
                    .clipped()

                    Text(Self.formatDuration(item.duration))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: .capsule)
                        .padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    Text(item.qualityLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: .capsule)
                        .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    if isSelectionMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(isSelected ? Color("BiliPink") : .white.opacity(0.92))
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .heroTransitionSource(id: heroID, in: namespace)

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        Text(item.uploader)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(sizeText)
                            .font(.system(size: 11))
                            .foregroundStyle(item.status == .failed ? .red : .secondary)
                            .lineLimit(1)
                    }

                    if item.status == .downloading || item.status == .queued || item.status == .paused {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(progressText)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 2){
                                ProgressView(value: item.progress)
                                    .tint(Color("BiliPink"))

                                Text(speedText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 65)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(10)
            .frame(height: 108)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                isSelected ? Color("BiliPink").opacity(0.55) : Color.white.opacity(0.14),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    }
            )
            .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label("选择", systemImage: "checkmark.circle")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var progressText: String {
        let downloaded = CacheStorageService.formattedSize(item.downloadedBytes)
        let total = item.totalBytes > 0 ? CacheStorageService.formattedSize(item.totalBytes) : "--"
        return "\(downloaded) / \(total)"
    }

    private var speedText: String {
        let base: String
        switch item.status {
        case .queued:
            base = "等待下载"
        case .paused:
            base = "暂停"
        default:
            base = ""
        }
        guard item.speedBytesPerSecond > 0 else { return base }
        return "\(base)  \(CacheStorageService.formattedSize(Int64(item.speedBytesPerSecond))) /s"
    }

    private var sizeText: String {
        if item.status == .failed {
            return item.errorMessage ?? "下载失败"
        }
        return CacheStorageService.formattedSize(max(item.fileSizeBytes, item.totalBytes))
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let sanitized = max(seconds, 0)
        let h = sanitized / 3600
        let m = (sanitized % 3600) / 60
        let s = sanitized % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

#Preview {
    NavigationStack {
        OfflineCacheView(initialPrefill: nil)
    }
}

private extension View {
    @ViewBuilder
    func heroTransitionSource(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            matchedGeometryEffect(id: id, in: namespace)
        }
    }
}
