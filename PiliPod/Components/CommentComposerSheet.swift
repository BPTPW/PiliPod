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
    let onDismiss: () -> Void
    let onPosted: () -> Void

    @State private var text: String = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [SelectedCommentImage] = []
    @State private var isPosting = false
    @State private var errorText: String?

    private let maxImageCount = 9

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextEditor(text: $text)
                    .frame(minHeight: 96, maxHeight: 140)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("说点什么吧…")
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

                HStack {
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
                            .glassEffect(
                                .regular.interactive(),
                                in: .circle
                            )
                    }
                    .disabled(selectedImages.count >= maxImageCount || isPosting)
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

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("发送评论")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { onDismiss() }
                        .disabled(isPosting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isPosting {
                            ProgressView()
                        } else {
                            Text("发送")
                                .fontWeight(.semibold)
                        }
                    }
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
                pictures: picturePayloads
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
                    imgSrc: upload.imageURL.replacingOccurrences(of: "http://", with: "https://"),
                    imgWidth: upload.imageWidth,
                    imgHeight: upload.imageHeight,
                    imgSize: upload.imgSize
                )
            )
        }

        return payloads
    }
}

private struct SelectedCommentImage: Identifiable {
    let id = UUID()
    let uiImage: UIImage
}
