import SwiftUI
import UniformTypeIdentifiers

private struct OfflineCacheTransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .zip, .json] }
    static var writableContentTypes: [UTType] { [.data, .zip, .json] }

    let data: Data

    init(sourceURL: URL) {
        data = (try? Data(contentsOf: sourceURL)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

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
    @State private var itemPendingExport: OfflineCacheItem?
    @State private var exportOptions: [OfflineCacheExportOption] = []
    @State private var exportDocument = OfflineCacheTransferDocument(
        sourceURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-cache-placeholder.txt")
    )
    @State private var exportFilename = "offline-cache-export.zip"
    @State private var exportContentType: UTType = .zip
    @State private var isExporterPresented = false
    @State private var isPreparingExport = false
    @State private var exportProgress = 0.0
    @State private var exportStage = "正在准备"
    @State private var exportCurrentStep = 0
    @State private var exportTotalSteps = 0
    @State private var exportCancellationToken: OfflineExportCancellationToken?
    @State private var isImporterPresented = false
    @State private var transferErrorTitle: String?
    @State private var transferErrorMessage: String?
    @State private var toastMessage: String?
    @Namespace private var videoNamespace

    var body: some View {
        List {
            if cacheManager.sortedItems.isEmpty {
                emptyState
                    .offlineCacheListRow()
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
                            presentDeleteDialog(for: item)
                        },
                        onSelect: {
                            enterSelectionMode(selecting: item.id)
                        }
                    )
                    .padding(.vertical, 7)
                    .offlineCacheListRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !isSelectionMode {
                            Button(role: .destructive) {
                                deleteItemImmediately(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }

                            if item.status == .completed {
                                Button {
                                    presentExportOptions(for: item)
                                } label: {
                                    Label("导出", systemImage: "square.and.arrow.up")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
                    Menu {
                        Button {
                            presentAddTaskSheet(prefill: nil, autoQuery: false)
                        } label: {
                            Label("添加缓存任务", systemImage: "plus")
                        }

                        Button {
                            isImporterPresented = true
                        } label: {
                            Label("导入缓存文件", systemImage: "square.and.arrow.down")
                        }
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
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.zip]
        ) { result in
            handleImportResult(result)
            isImporterPresented = false
        }
        .modifier(OfflineCacheExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            exportContentType: exportContentType,
            defaultFilename: exportFilename,
            onComplete: handleExportResult
        ))
        .sheet(isPresented: $isPreparingExport) {
            ExportProgressSheet(progress: exportProgress, stage: exportStage, currentStep: exportCurrentStep, totalSteps: exportTotalSteps) {
                exportCancellationToken?.cancel()
            }
                .interactiveDismissDisabled(true)
                .presentationDetents([.height(190)])
                .presentationDragIndicator(.hidden)
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
        .alert(
            itemPendingExport.map { "导出 \($0.title)" } ?? "导出缓存",
            isPresented: Binding(
                get: { itemPendingExport != nil && !exportOptions.isEmpty },
                set: { isPresented in
                    if !isPresented {
                        dismissExportOptions()
                    }
                }
            )
        ) {
            ForEach(exportOptions) { option in
                if option.kind == .packageZip {
                    Button(option.title) {
                        export(item: itemPendingExport, option: option)
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(option.title) {
                        export(item: itemPendingExport, option: option)
                    }
                }
            }
            Button("取消", role: .cancel) {
                dismissExportOptions()
            }
        } message: {
            Text("选择要导出的缓存内容")
        }
        .alert(
            transferErrorTitle ?? "导入导出",
            isPresented: Binding(
                get: { transferErrorMessage != nil },
                set: { if !$0 {
                    transferErrorTitle = nil
                    transferErrorMessage = nil
                } }
            )
        ) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(transferErrorMessage ?? "未知错误")
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

    private func presentDeleteDialog(for item: OfflineCacheItem) {
        itemPendingDeletion = item
        isSingleDeleteDialogPresented = true
    }

    private func presentExportOptions(for item: OfflineCacheItem) {
        let options = OfflineCacheTransferService.exportOptions(for: item)
        guard !options.isEmpty else {
            transferErrorTitle = "导出失败"
            transferErrorMessage = "当前缓存没有可导出的文件。"
            return
        }
        itemPendingExport = item
        exportOptions = options
    }

    private func dismissExportOptions() {
        itemPendingExport = nil
        exportOptions = []
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

    private func deleteItemImmediately(_ item: OfflineCacheItem) {
        cacheManager.deleteItem(id: item.id)
    }

    private func export(item: OfflineCacheItem?, option: OfflineCacheExportOption) {
        guard let item else { return }
        if option.kind == .packageZip {
            dismissExportOptions()
            isPreparingExport = true
            exportProgress = 0
            exportStage = "正在准备缓存文件"
            exportCurrentStep = 0
            exportTotalSteps = 0
            let cancellationToken = OfflineExportCancellationToken()
            exportCancellationToken = cancellationToken
            let itemCopy = item
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let file = try OfflineCacheTransferService.prepareExport(
                        for: itemCopy,
                        option: .packageZip,
                        progress: { index, total, progress, stage in
                            DispatchQueue.main.async {
                                exportProgress = progress
                                exportStage = stage
                                exportCurrentStep = min(index + 1, total)
                                exportTotalSteps = total
                            }
                        },
                        isCancelled: { cancellationToken.isCancelled }
                    )
                    DispatchQueue.main.async {
                        isPreparingExport = false
                        exportCancellationToken = nil
                        exportDocument = OfflineCacheTransferDocument(sourceURL: file.url)
                        exportFilename = file.filename
                        exportContentType = file.contentType
                        isExporterPresented = true
                    }
                } catch {
                    DispatchQueue.main.async {
                        isPreparingExport = false
                        exportCancellationToken = nil
                        transferErrorTitle = "导出失败"
                        transferErrorMessage = error.localizedDescription
                    }
                }
            }
            return
        }
        do {
            let file = try OfflineCacheTransferService.prepareExport(
                for: item,
                option: option.kind
            )
            exportDocument = OfflineCacheTransferDocument(sourceURL: file.url)
            exportFilename = file.filename
            exportContentType = file.contentType
            dismissExportOptions()
            isExporterPresented = true
        } catch {
            transferErrorTitle = "导出失败"
            transferErrorMessage = error.localizedDescription
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            toastMessage = "导出成功"
        case let .failure(error):
            transferErrorTitle = "导出失败"
            transferErrorMessage = error.localizedDescription
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            do {
                let importedItem = try cacheManager.importCacheArchive(from: url)
                toastMessage = "已导入 \(importedItem.title)"
            } catch {
                transferErrorTitle = "导入失败"
                transferErrorMessage = error.localizedDescription
            }
        case let .failure(error):
            transferErrorTitle = "导入失败"
            transferErrorMessage = error.localizedDescription
        }
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

private struct OfflineCacheExporter: ViewModifier {
    @Binding var isPresented: Bool
    let document: OfflineCacheTransferDocument
    let exportContentType: UTType
    let defaultFilename: String
    let onComplete: (Result<URL, Error>) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        switch exportContentType {
        case .json:
            content.fileExporter(
                isPresented: $isPresented,
                document: document,
                contentType: .json,
                defaultFilename: defaultFilename,
                onCompletion: onComplete
            )
        case .zip:
            content.fileExporter(
                isPresented: $isPresented,
                document: document,
                contentType: .zip,
                defaultFilename: defaultFilename,
                onCompletion: onComplete
            )
        default:
            content.fileExporter(
                isPresented: $isPresented,
                document: document,
                contentType: .data,
                defaultFilename: defaultFilename,
                onCompletion: onComplete
            )
        }
    }
}

private final class OfflineExportCancellationToken {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}

private struct ExportProgressSheet: View {
    let progress: Double
    let stage: String
    let currentStep: Int
    let totalSteps: Int
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(totalSteps > 0 ? "步骤 \(currentStep)/\(totalSteps)" : "准备中")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress, total: 1)
                    .progressViewStyle(.linear)
                Text(stage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(20)
            .navigationTitle("导出缓存文件包")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消", role: .cancel, action: onCancel)
                }
            }
        }
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
    func offlineCacheListRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    @ViewBuilder
    func heroTransitionSource(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            matchedGeometryEffect(id: id, in: namespace)
        }
    }
}
