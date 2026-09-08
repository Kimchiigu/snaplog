//
//  RoomListView.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import SwiftUI

/// Home feed listing the user's rooms, with live recording presence.
struct RoomListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = RoomListViewModel(apiClient: AppDependencies.apiClient)

    @State private var showingCreateSheet = false
    @State private var showingJoinSheet = false
    @State private var recordingRoom = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.rooms.isEmpty {
                    ProgressView("Loading rooms…")
                } else if viewModel.rooms.isEmpty {
                    emptyState
                } else {
                    roomFeed
                }
            }
            .navigationTitle("Rooms")
            .toolbar { toolbarContent }
            .refreshable { await viewModel.loadRooms() }
            .task {
                viewModel.startObservingPresence()
                await viewModel.loadRooms()
            }
            .onDisappear { viewModel.stopObservingPresence() }
            .sheet(isPresented: $showingCreateSheet) {
                CreateRoomSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showingJoinSheet) {
                JoinRoomSheet(viewModel: viewModel)
            }
            .fullScreenCover(isPresented: $recordingRoom) {
                CameraView()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Sign Out") {
                appState.signOut()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Create Room", systemImage: "plus") { showingCreateSheet = true }
                Button("Join Room", systemImage: "person.badge.plus") { showingJoinSheet = true }
            } label: {
                Label("Room Actions", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    private var roomFeed: some View {
        let gridRooms = viewModel.rooms.filter { viewModel.usesGridLayout(for: $0) }
        let stackRooms = viewModel.rooms.filter { !viewModel.usesGridLayout(for: $0) }

        List {
            if !gridRooms.isEmpty {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(gridRooms) { room in
                            roomCard(room)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                }
            }
            if !stackRooms.isEmpty {
                Section {
                    ForEach(stackRooms) { room in
                        roomCard(room)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func roomCard(_ room: Room) -> some View {
        Button {
            recordingRoom = true
        } label: {
            RoomCard(
                room: room,
                showsRecordingIndicator: viewModel.recordingRoomIDs.contains(room.id)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Rooms Yet", systemImage: "person.3")
        } description: {
            Text("Create a room or join one with a code to start logging.")
        } actions: {
            PrimaryButton(title: "Create Room", systemImage: "plus") { showingCreateSheet = true }
                .padding(.horizontal)
        }
    }
}

#Preview {
    RoomListView()
        .environment(AppState())
}
