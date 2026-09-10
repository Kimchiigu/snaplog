
import SwiftUI

struct RoomListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = RoomListViewModel(apiClient: AppDependencies.apiClient)

    private enum DockTab: String, CaseIterable, Identifiable {
        case camera
        case logs
        var id: String { rawValue }
    }

    @State private var selectedTab: DockTab = .logs
    @State private var showingCreateSheet = false
    @State private var showingJoinSheet = false
    @State private var showingProfile = false
    @State private var showingCamera = false
    @State private var showingNotifications = false
    @State private var notificationItems: [RoomListViewModel.NotificationItem] = []
    @State private var navigationPath: [Room] = []
    @State private var rotationDetector = RotationDetector()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottom) {
                Theme.canvas.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    roomList
                }
                dock
                if let notice = viewModel.newLogNotice {
                    NewLogNoticeCard(notice: notice) {
                        viewModel.dismissNotice()
                        if let room = viewModel.rooms.first(where: { $0.id == notice.roomID }) {
                            navigationPath = [room]
                        }
                    } onDismiss: {
                        viewModel.dismissNotice()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: viewModel.newLogNotice)
            .preferredColorScheme(.dark)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Room.self) { room in
                RoomDetailView(room: room)
            }
            .task {
                viewModel.currentUserName = appState.currentUser?.displayName
                if let token = appState.authToken {
                    viewModel.startObservingPresence(token: token)
                }
                await viewModel.loadRooms()
            }
            .onDisappear {
                viewModel.stopObservingPresence()
                rotationDetector.stop()
            }
            .task { rotationDetector.start() }
            .onChange(of: rotationDetector.isLandscape) { _, isLandscape in
                showingCamera = isLandscape
            }
            .refreshable { await viewModel.loadRooms() }
            .sheet(isPresented: $showingCreateSheet) {
                CreateRoomSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showingJoinSheet) {
                JoinRoomSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
                    .environment(appState)
            }
            .sheet(isPresented: $showingNotifications) {
                NotificationsListView(items: notificationItems) { roomID in
                    if let room = viewModel.rooms.first(where: { $0.id == roomID }) {
                        navigationPath = [room]
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera, onDismiss: {
                selectedTab = .logs
                Task { await viewModel.loadRooms() }
            }) {
                CameraView(room: viewModel.rooms.first)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Theme.brandText("SNAPLOG")
                Spacer()
                Button {
                    showingProfile = true
                } label: {
                    ZStack {
                        SmileyIcon(color: Theme.pink, size: 20)
                            .frame(width: 44, height: 44)
                    }
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Profile")
            }
            HStack(spacing: 6) {
                SmileyIcon(color: Theme.accent, size: 14)
                Text("rotate to capture")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var roomList: some View {
        if viewModel.isLoading && viewModel.rooms.isEmpty {
            Spacer()
            ProgressView()
            Spacer()
        } else if viewModel.rooms.isEmpty {
            Spacer()
            emptyState
            Spacer()
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    if let message = viewModel.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(viewModel.rooms) { room in
                        NavigationLink(value: room) {
                            RoomCard(
                                room: room,
                                showsRecordingIndicator: viewModel.freshRoomIDs.contains(room.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 140) // clears the floating dock
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            SmileyIcon(color: Theme.muted, size: 44)
            Text("No Rooms Yet")
                .font(.title3.weight(.semibold))
            Text("Create a room or join one with an invite code to start logging.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Create Room", systemImage: "plus") { showingCreateSheet = true }
                .padding(.horizontal, 48)
        }
        .padding(.horizontal, 24)
    }

    private var dock: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 20) {
                Button {
                    notificationItems = viewModel.takeNotifications()
                    showingNotifications = true
                } label: {
                    Image(systemName: "bell")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.tint(.black.opacity(0.6)), in: .circle)
                .overlay(alignment: .topTrailing) {
                    if viewModel.unreadNotificationCount > 0 {
                        Text("\(viewModel.unreadNotificationCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.canvas)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Circle().fill(Theme.pink))
                            .offset(x: 4, y: -4)
                    }
                }
                .accessibilityLabel("Notifications")

                dockTabs

                Menu {
                    Button("Create Room", systemImage: "plus") { showingCreateSheet = true }
                    Button("Join Room", systemImage: "person.badge.plus") { showingJoinSheet = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.canvas)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Theme.accent))
                }
                .accessibilityLabel("Create or join a room")
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var dockTabs: some View {
        HStack(spacing: 4) {
            ForEach(DockTab.allCases) { tab in
                Button {
                    selectedTab = tab
                    if tab == .camera { showingCamera = true }
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedTab == tab ? .white : Theme.muted)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(selectedTab == tab ? Theme.cardElevated : .clear)
                        )
                }
                .accessibilityLabel("\(tab.rawValue) tab")
            }
        }
        .padding(4)
        .glassEffect(.regular.tint(.black.opacity(0.6)), in: .capsule)
    }
}

#Preview {
    RoomListView()
        .environment(AppState())
}
