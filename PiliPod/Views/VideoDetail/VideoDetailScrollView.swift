import SwiftUI

struct VideoDetailScrollLayout {
    let range: CGFloat
    @Binding var fraction: CGFloat
    let isActive: Bool

    var collapsed: CGFloat { fraction * range }
}

extension EnvironmentValues {
    @Entry var videoDetailScrollLayout = VideoDetailScrollLayout(range: 0, fraction: .constant(0), isActive: false)
}

/// Keeps the native scroll viewport stationary while the player and tab bar move above it.
struct VideoDetailScrollView<Content: View>: View {
    @Environment(\.videoDetailScrollLayout) private var layout
    @State private var position = ScrollPosition(edge: .top)
    @State private var isUserScrolling = false
    @State private var readingOffset: CGFloat = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let remaining = layout.range - layout.collapsed
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height + remaining, alignment: .top)
                    .padding(.top, layout.range)
            }
            .scrollPosition($position)
            .onScrollPhaseChange { _, phase, context in
                if phase == .interacting {
                    isUserScrolling = layout.isActive
                }
                if isUserScrolling, layout.isActive {
                    updatePlayer(for: context.geometry)
                }
                if phase == .idle || phase == .tracking {
                    isUserScrolling = false
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, offset in
                if layout.isActive, isUserScrolling { updatePlayer(at: offset) }
            }
            // The top padding scrolls away underneath the tab bar. Extending the
            // viewport by the same remaining distance avoids counting a drag twice.
            .padding(.top, -remaining)
            .clipped()
            .contentShape(Rectangle())
            .onAppear {
                alignWithPlayer()
            }
            .onChange(of: layout.collapsed) {
                if !layout.isActive || !isUserScrolling { alignWithPlayer() }
            }
            .onChange(of: layout.isActive) {
                isUserScrolling = false
                alignWithPlayer()
            }
        }
    }

    private func updatePlayer(for geometry: ScrollGeometry) {
        updatePlayer(at: max(0, geometry.contentOffset.y + geometry.contentInsets.top))
    }

    private func updatePlayer(at offset: CGFloat) {
        // A tab reopened mid-list keeps its current header height until its own
        // content reaches the top. From there the spacer consumes the drag.
        var collapsed = layout.collapsed
        if readingOffset == 0 || offset < collapsed {
            collapsed = min(offset, layout.range)
            if layout.range > 0, collapsed != layout.collapsed {
                layout.fraction = collapsed / layout.range
            }
        }
        readingOffset = max(0, offset - collapsed)
    }

    private func alignWithPlayer() {
        // Each tab owns its reading offset. Only the spacer scrolls when the
        // other tab moves the player, even if this tab is deep in its content.
        withTransaction(Transaction(animation: nil)) {
            position.scrollTo(y: layout.collapsed + readingOffset)
        }
    }
}
