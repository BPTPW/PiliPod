import Foundation
import SwiftUI

struct FollowingListView: View {
    @StateObject private var viewModel: FollowingListViewModel
    @State private var selectedRoute: FollowingUserRoute?
    @State private var searchText = ""
    @State private var isSearchPresented = false

    init(mid: Int) {
        _viewModel = StateObject(wrappedValue: FollowingListViewModel(mid: mid))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
            .padding(16)
        }
        .scrollDismissesKeyboard(.immediately)
        .ignoresSafeArea(.container, edges: .bottom)
        .background(Color(.systemBackground))
        .navigationTitle("关注")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: Text("followinglist.search.placeholder")
        )
        .onSubmit(of: .search) {
            submitSearch(keyword: searchText)
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                viewModel.clearSearch()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isSearchPresented = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                
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
                    Image(systemName: "arrow.up.arrow.down")
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

    private func submitSearch(keyword: String) {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        Task { await viewModel.search(keyword: keyword) }
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
