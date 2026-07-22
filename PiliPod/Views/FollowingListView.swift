import Foundation
import SwiftUI
import UIKit

struct FollowingListView: View {
    @StateObject private var viewModel: FollowingListViewModel
    @State private var selectedRoute: FollowingUserRoute?
    @State private var searchText = ""
    @State private var isSearchFieldFocused = false

    init(mid: Int) {
        _viewModel = StateObject(wrappedValue: FollowingListViewModel(mid: mid))
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear
                        .frame(height: 48)

                    if isLoading && displayedUsers.isEmpty {
                        ProgressView("加载关注列表中…")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else if let errorMessage, displayedUsers.isEmpty {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else if displayedUsers.isEmpty {
                        Text(viewModel.searchKeyword == nil ? "还没有关注的用户" : "没有找到匹配的用户")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(displayedUsers) { user in
                                UserSmallCardView(
                                    user: user.cardUser,
                                    subtitle: user.sign,
                                    initialFollowState: true
                                ) {
                                    selectedRoute = FollowingUserRoute(mid: user.mid)
                                }
                            }

                            if viewModel.searchKeyword == nil, viewModel.hasMore {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear {
                                        Task { await viewModel.loadMore() }
                                    }
                            }

                            if viewModel.isLoading && viewModel.searchKeyword == nil {
                                ProgressView()
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .scrollDismissesKeyboard(.immediately)
            .ignoresSafeArea(.container, edges: .bottom)

            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .zIndex(1)
        }
        .background(Color(.systemBackground))
        .navigationTitle("关注")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(FollowingListViewModel.SortOption.allCases) { option in
                        Button {
                            Task {
                                guard viewModel.sortOption != option else { return }
                                viewModel.sortOption = option
                                await viewModel.refresh()
                            }
                        } label: {
                            if viewModel.sortOption == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "list.number")
                }
            }
        }
        .navigationDestination(item: $selectedRoute) { route in
            UserSpaceView(mid: route.mid)
        }
        .task {
            await viewModel.refresh()
        }
    }

    private var displayedUsers: [FollowingUser] {
        viewModel.searchKeyword == nil ? viewModel.users : viewModel.searchUsers
    }

    private var isLoading: Bool {
        viewModel.searchKeyword == nil ? viewModel.isLoading : viewModel.isSearching
    }

    private var errorMessage: String? {
        viewModel.searchKeyword == nil ? viewModel.errorMessage : viewModel.searchErrorMessage
    }

    private var searchBar: some View {
        HStack(spacing: shouldShowClearButton ? 8 : 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                FollowingSearchTextField(
                    text: $searchText,
                    isFocused: $isSearchFieldFocused,
                    onSubmit: submitSearch
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .glassEffect(.regular.interactive(), in: .capsule)

            Button {
                searchText = ""
                viewModel.clearSearch()
                isSearchFieldFocused = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(.primary)
            .opacity(shouldShowClearButton ? 1 : 0)
            .scaleEffect(shouldShowClearButton ? 1 : 0.7)
            .allowsHitTesting(shouldShowClearButton)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityHidden(!shouldShowClearButton)
            .frame(width: shouldShowClearButton ? 44 : 0, height: 44)
            .clipped()
            .animation(.snappy(duration: 0.25), value: shouldShowClearButton)
        }
        .animation(.snappy(duration: 0.25), value: shouldShowClearButton)
    }

    private func submitSearch(keyword: String) {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        Task { await viewModel.search(keyword: keyword) }
    }

    private var shouldShowClearButton: Bool {
        isSearchFieldFocused || !searchText.isEmpty || viewModel.searchKeyword != nil
    }
}

private struct FollowingSearchTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSubmit: (String) -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.placeholder = L10n.string("followinglist.search.placeholder")
        textField.font = .preferredFont(forTextStyle: .body)
        textField.textColor = .label
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.returnKeyType = .search
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text, textField.markedTextRange == nil {
            textField.text = text
        }

        if isFocused, !textField.isFirstResponder {
            textField.becomeFirstResponder()
        } else if !isFocused, textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private var parent: FollowingSearchTextField

        init(parent: FollowingSearchTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            if textField.markedTextRange != nil {
                textField.unmarkText()
            }

            let submittedText = textField.text ?? ""
            parent.text = submittedText
            parent.onSubmit(submittedText)
            parent.isFocused = false
            textField.resignFirstResponder()
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if textField.markedTextRange != nil {
                textField.unmarkText()
            }
            parent.text = textField.text ?? ""
            parent.isFocused = false
        }
    }
}

private struct FollowingUserRoute: Identifiable, Hashable {
    let mid: Int

    var id: Int { mid }
}

#Preview {
    NavigationStack {
        FollowingListView(mid: 2)
    }
}
