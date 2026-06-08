import SwiftUI

struct FollowingListView: View {
    @StateObject private var viewModel: FollowingListViewModel
    @State private var selectedRoute: FollowingUserRoute?

    init(mid: Int) {
        _viewModel = StateObject(wrappedValue: FollowingListViewModel(mid: mid))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading && viewModel.users.isEmpty {
                    ProgressView("加载关注列表中…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let error = viewModel.errorMessage, viewModel.users.isEmpty {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if viewModel.users.isEmpty {
                    Text("还没有关注的用户")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.users) { user in
                            UserSmallCardView(
                                user: user.cardUser,
                                subtitle: user.sign,
                                initialFollowState: true
                            ) {
                                selectedRoute = FollowingUserRoute(mid: user.mid)
                            }
                        }

                        if viewModel.hasMore {
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                    Task { await viewModel.loadMore() }
                                }
                        }

                        if viewModel.isLoading {
                            ProgressView()
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
            .padding(16)
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
