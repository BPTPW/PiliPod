//
//  CommentComposerSheet.swift
//  PiliPod
//
//  Created by Codex on 2026/6/1.
//

import PhotosUI
import SwiftUI
import UIKit

struct CommentComposerSheet: View {
    let aid: Int
    let titleText: String
    let placeholderText: String
    let rootRpid: Int?
    let parentRpid: Int?
    let onDismiss: () -> Void
    let onEmotePanelVisibilityChanged: (Bool) -> Void
    let onPosted: () -> Void

    @State private var text: String = ""
    @State private var selectedRange: NSRange = .init(location: 0, length: 0)
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [SelectedCommentImage] = []
    @State private var isPosting = false
    @State private var errorText: String?
    @State private var isEmotePanelShown = false
    @State private var emotePackages: [ReplyEmotePackage] = []
    @State private var selectedPackageID: Int?
    @State private var isLoadingEmotes = false

    private let maxImageCount = 9

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                CursorTextView(
                    text: $text,
                    selectedRange: $selectedRange,
                    onBeginEditing: {
                        isEmotePanelShown = false
                        onEmotePanelVisibilityChanged(false)
                    }
                )
                .frame(minHeight: 96, maxHeight: 140)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholderText)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

                if !selectedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(selectedImages) { image in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image.uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 86, height: 86)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                    Button {
                                        selectedImages.removeAll { $0.id == image.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .padding(4)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    PhotosPicker(
                        selection: $photoItems,
                        maxSelectionCount: max(0, maxImageCount - selectedImages.count),
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "photo.badge.plus")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .disabled(selectedImages.count >= maxImageCount || isPosting)
                    .buttonStyle(.plain)

                    Button {
                        hideKeyboard()
                        isEmotePanelShown.toggle()
                        onEmotePanelVisibilityChanged(isEmotePanelShown)
                        if isEmotePanelShown, emotePackages.isEmpty {
                            Task { await loadEmotesIfNeeded() }
                        }
                    } label: {
                        Image(systemName: "face.smiling")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .disabled(isPosting)
                    .tint(.primary)

                    Spacer()

                    Text("\(text.count)/1000")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isEmotePanelShown {
                    emotePanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Spacer(minLength: 0)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isEmotePanelShown)
            .padding(16)
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                    .disabled(isPosting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isPosting {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane")
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit || isPosting)
                }
            }
            .onChange(of: photoItems) { _, newValue in
                Task { await loadPickedItems(newValue) }
            }
        }
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 1000
    }

    private var currentEmotes: [ReplyEmoteItem] {
        guard let selectedPackageID else { return emotePackages.first?.emote ?? [] }
        return emotePackages.first(where: { $0.id == selectedPackageID })?.emote ?? []
    }

    private var emotePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoadingEmotes {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("加载表情中…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            } else if emotePackages.isEmpty {
                Text("暂无可用表情包")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(emotePackages) { pkg in
                            Button {
                                selectedPackageID = pkg.id
                            } label: {
                                Group {
                                    if let url = URL(string: normalizedHTTPS(pkg.url)), isValidRemoteURL(pkg.url) {
                                        CachedAsyncImage(url: url) { phase in
                                            if case .success(let image) = phase {
                                                image.resizable().scaledToFit()
                                            } else {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color.secondary.opacity(0.12))
                                            }
                                        }
                                    } else {
                                        Text("Aa")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                    }
                                }
                                .frame(width: 26, height: 26)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill((selectedPackageID ?? emotePackages[0].id) == pkg.id ? Color.secondary.opacity(0.14) : .clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 44, maximum: 56), spacing: 6)
                        ],
                        alignment: .leading,
                        spacing: 6
                    ) {
                        ForEach(currentEmotes) { emote in
                            Button {
                                insertEmoteToken(emote.text)
                            } label: {
                                Group {
                                    if let url = URL(string: normalizedHTTPS(emote.url)), isValidRemoteURL(emote.url) {
                                        CachedAsyncImage(url: url) { phase in
                                            if case .success(let image) = phase {
                                                image.resizable().scaledToFit()
                                            } else {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color.secondary.opacity(0.12))
                                            }
                                        }
                                        .frame(
                                            width: emoteSize(for: emote),
                                            height: emoteSize(for: emote)
                                        )
                                    } else {
                                        Text(emote.text)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                            .frame(height: 22)
                                            .padding(.horizontal, 6)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
                .frame(maxHeight: 250)
            }
        }
    }

    @MainActor
    private func loadPickedItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        defer { photoItems = [] }

        for item in items {
            if selectedImages.count >= maxImageCount { break }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { continue }
            selectedImages.append(SelectedCommentImage(uiImage: uiImage))
        }
    }

    @MainActor
    private func loadEmotesIfNeeded() async {
        guard emotePackages.isEmpty, !isLoadingEmotes else { return }
        isLoadingEmotes = true
        defer { isLoadingEmotes = false }

        do {
            let packages = try await BiliAPI.shared.fetchUserReplyEmotePackages()
            emotePackages = packages
            selectedPackageID = packages.first?.id
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        isPosting = true
        errorText = nil
        defer { isPosting = false }

        do {
            var picturePayloads: [CommentPictureUploadPayload] = []
            if !selectedImages.isEmpty {
                picturePayloads = try await uploadImages()
            }

            _ = try await BiliAPI.shared.addVideoComment(
                oid: aid,
                message: text.trimmingCharacters(in: .whitespacesAndNewlines),
                pictures: picturePayloads,
                root: rootRpid,
                parent: parentRpid
            )
            onPosted()
            onDismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func uploadImages() async throws -> [CommentPictureUploadPayload] {
        var payloads: [CommentPictureUploadPayload] = []

        for (index, selected) in selectedImages.enumerated() {
            guard let jpegData = selected.uiImage.jpegData(compressionQuality: 0.88) else { continue }
            let upload = try await BiliAPI.shared.uploadCommentImage(
                data: jpegData,
                fileName: "comment_\(index).jpg"
            )
            payloads.append(
                CommentPictureUploadPayload(
                    imgSrc: normalizedHTTPS(upload.imageURL),
                    imgWidth: upload.imageWidth,
                    imgHeight: upload.imageHeight,
                    imgSize: upload.imgSize
                )
            )
        }

        return payloads
    }

    private func insertEmoteToken(_ token: String) {
        let safeLocation = min(max(0, selectedRange.location), text.utf16.count)
        let nsText = text as NSString
        let newText = nsText.replacingCharacters(in: NSRange(location: safeLocation, length: selectedRange.length), with: token)
        text = newText
        let next = safeLocation + (token as NSString).length
        selectedRange = NSRange(location: next, length: 0)
    }

    private func normalizedHTTPS(_ raw: String) -> String {
        raw.replacingOccurrences(of: "http://", with: "https://")
    }

    private func isValidRemoteURL(_ raw: String) -> Bool {
        guard let url = URL(string: normalizedHTTPS(raw)),
              let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func emoteSize(for emote: ReplyEmoteItem) -> CGFloat {
        let sizeType = emote.meta?.size ?? 2
        return sizeType == 1 ? 28 : 48
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct SelectedCommentImage: Identifiable {
    let id = UUID()
    let uiImage: UIImage
}

private struct CursorTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let onBeginEditing: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.textColor = .label
        view.delegate = context.coordinator
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.selectedRange != selectedRange {
            uiView.selectedRange = selectedRange
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: CursorTextView
        init(_ parent: CursorTextView) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onBeginEditing()
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
        }
    }
}
