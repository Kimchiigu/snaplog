//
//  RoomListView.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import SwiftUI

/// Home: brand header, active room cards, and a floating bottom dock that
/// switches between the camera and the room log list.
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

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Theme.canvas.ignoresSafeArea()
                    VStack(spacing: 0) {
                        header
                        roomList
                    }
                    dock
                }
                // Rotating the phone jumps straight into the camera.
                .onChange(of: geo.size.width > geo.size.height) { _, isLandscape in
                    showingCamera = isLandscape
                }
            }
            .preferredColorScheme(.dark)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Room.self) { room in
                RoomDetailView(room: room)
            }
            .task {
                if let token = appState.authToken {
                    viewModel.startObservingPresence(token: token)
                }
                await viewModel.loadRooms()
            }
            .onDisappear { viewModel.stopObservingPresence() }
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
            .fullScreenCover(isPresented: $showingCamera, onDismiss: {
                selectedTab = .logs
                Task { await viewModel.loadRooms() }
            }) {
                CameraView(room: viewModel.rooms.first)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Theme.brandText("SNAPLOG")
                Spacer()
                Button {
                    showingProfile = true
                } label: {
                    ZStack {
                        Circle().fill(Theme.card)
                            .frame(width: 44, height: 44)
                        SmileyIcon(color: Theme.pink, size: 20)
                    }
                }
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

    // MARK: - Room list

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

    // MARK: - Bottom dock

    private var dock: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 20) {
                Button {} label: {
                    Image(systemName: "bell")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.tint(.black.opacity(0.6)), in: .circle)
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
