//
//  FullscreenImageViewer.swift
//  PiliPod
//
//  Created by Codex on 2026/5/30.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
import VisionKit
import Photos
#endif

struct FullscreenImageViewer: View {
    let imageURL: String
    let onDismiss: () -> Void

    @State private var dragOffsetY: CGFloat = 0
    @State private var zoomScale: CGFloat = 1
    @State private var currentImage: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            ZoomableLiveImageView(
                imageURL: imageURL,
                zoomScale: $zoomScale,
                onImageLoaded: { image in
                    currentImage = image
                }
            )
            .ignoresSafeArea()
            .offset(y: dragOffsetY)
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        guard zoomScale <= 1.01, value.translation.height > 0 else { return }
                        dragOffsetY = value.translation.height
                    }
                    .onEnded { value in
                        guard zoomScale <= 1.01 else {
                            dragOffsetY = 0
                            return
                        }
                        if value.translation.height > 120 || value.predictedEndTranslation.height > 180 {
                            onDismiss()
                        } else {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                dragOffsetY = 0
                            }
                        }
                    }
            )

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .padding(.top, 18)
            .padding(.trailing, 16)

            VStack {
                Spacer()
                HStack {
                    Button {
                        saveImageToPhotoLibrary()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .disabled(currentImage == nil)

                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.bottom, 22)
            }
        }
        .statusBarHidden(true)
    }

    private var backgroundOpacity: Double {
        let progress = min(max(dragOffsetY / 220, 0), 1)
        return 1 - Double(progress) * 0.45
    }

    private func saveImageToPhotoLibrary() {
        guard let image = currentImage else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        }
    }
}

#if canImport(UIKit)
private struct ZoomableLiveImageView: UIViewRepresentable {
    let imageURL: String
    @Binding var zoomScale: CGFloat
    let onImageLoaded: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true

        let imageView = context.coordinator.imageView
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)

        context.coordinator.attachLiveTextIfAvailable()
        context.coordinator.loadImage(urlString: imageURL)
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.currentURL != imageURL {
            uiView.setZoomScale(1, animated: false)
            context.coordinator.loadImage(urlString: imageURL)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableLiveImageView
        let imageView = UIImageView()
        var currentURL: String?
        private var analysisInteraction: AnyObject?

        init(parent: ZoomableLiveImageView) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            parent.zoomScale = scrollView.zoomScale
            centerImage(in: scrollView)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = imageView.superview as? UIScrollView else { return }
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: true)
                return
            }

            let point = gesture.location(in: imageView)
            let targetZoom: CGFloat = 2.5
            let width = scrollView.bounds.width / targetZoom
            let height = scrollView.bounds.height / targetZoom
            let rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
            scrollView.zoom(to: rect, animated: true)
        }

        func loadImage(urlString: String) {
            currentURL = urlString
            guard let url = URL(string: urlString) else {
                imageView.image = nil
                return
            }
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    guard !Task.isCancelled,
                          let image = UIImage(data: data) else { return }
                    await MainActor.run {
                        guard self.currentURL == urlString else { return }
                        self.imageView.image = image
                        self.parent.onImageLoaded(image)
                        self.updateLiveTextAnalysis(with: image)
                    }
                } catch {
                    return
                }
            }
        }

        private func centerImage(in scrollView: UIScrollView) {
            let boundsSize = scrollView.bounds.size
            var frameToCenter = imageView.frame

            frameToCenter.origin.x = frameToCenter.size.width < boundsSize.width
                ? (boundsSize.width - frameToCenter.size.width) / 2 : 0
            frameToCenter.origin.y = frameToCenter.size.height < boundsSize.height
                ? (boundsSize.height - frameToCenter.size.height) / 2 : 0

            imageView.frame = frameToCenter
        }

        func attachLiveTextIfAvailable() {
            if #available(iOS 16.0, *) {
                let interaction = ImageAnalysisInteraction()
                interaction.preferredInteractionTypes = .automatic
                imageView.addInteraction(interaction)
                analysisInteraction = interaction
            }
        }

        func updateLiveTextAnalysis(with image: UIImage) {
            guard #available(iOS 16.0, *),
                  let interaction = analysisInteraction as? ImageAnalysisInteraction else { return }
            Task {
                let analyzer = ImageAnalyzer()
                do {
                    let analysis = try await analyzer.analyze(
                        image,
                        configuration: ImageAnalyzer.Configuration([.text, .machineReadableCode])
                    )
                    await MainActor.run {
                        interaction.analysis = analysis
                    }
                } catch {
                    return
                }
            }
        }
    }
}
#endif
