//
//  DashboardView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Main dashboard with drive list
//

import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedRoute: Route?
    @State private var showingDriveViewer = false
    @State private var showingDeviceStats = false
    @State private var showingErrorAlert = false
    @State private var hasUserDismissedError = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Network error banner (inline)
                        if let error = appState.error, showingErrorAlert {
                            errorBanner(error)
                        }

                        if appState.routes.isEmpty && !appState.isLoadingRoutes {
                            emptyState
                        } else if appState.routes.isEmpty && appState.isLoadingRoutes {
                            // Show skeleton loaders on initial load
                            ForEach(0..<5, id: \.self) { _ in
                                DriveCardSkeleton()
                            }
                        } else {
                            ForEach(appState.routes) { route in
                                DriveCard(route: route)
                                    .id(route.fullname) // Stable ID for view identity
                                    .onTapGesture {
                                        HapticManager.routeSelection()
                                        selectedRoute = route
                                        showingDriveViewer = true
                                    }
                            }

                            // Load more button or skeleton
                            if appState.isLoadingRoutes {
                                DriveCardSkeleton()
                            } else if appState.hasMoreRoutes {
                                Button {
                                    HapticManager.buttonPress()
                                    Task {
                                        await appState.loadMoreRoutes()
                                    }
                                } label: {
                                    Text("Load More")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                    .padding()
                }
                .refreshable {
                    HapticManager.refresh()
                    Task {
                        await appState.loadRoutes()
                    }
                }
            }
            .navigationTitle("Drives")
            .toolbar {
                // Device Stats Button - available for all devices
                if appState.selectedDevice != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            HapticManager.buttonPress()
                            showingDeviceStats = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            HapticManager.selection()
                            appState.timeFilterDays = 7
                            Task { await appState.loadRoutes() }
                        } label: {
                            Label("Past Week", systemImage: "calendar")
                        }

                        Button {
                            HapticManager.selection()
                            appState.timeFilterDays = 30
                            Task { await appState.loadRoutes() }
                        } label: {
                            Label("Past Month", systemImage: "calendar")
                        }

                        Button {
                            HapticManager.selection()
                            appState.timeFilterDays = AppConstants.maxTimeFilterDays
                            Task { await appState.loadRoutes() }
                        } label: {
                            Label("All Time", systemImage: "calendar")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }

                if let device = appState.selectedDevice {
                    ToolbarItem(placement: .principal) {
                        Text(device.displayName)
                            .font(.headline)
                            .id(device.dongleId) // Force refresh when device changes
                    }
                }
            }
            .id(appState.selectedDevice?.dongleId) // Force toolbar to re-render when device changes
            .fullScreenCover(item: $selectedRoute) { route in
                DriveViewerView(route: route)
                    .environment(appState)
            }
            .sheet(isPresented: $showingDeviceStats) {
                if let device = appState.selectedDevice {
                    DeviceStatsSheet(device: device, apiClient: appState.apiClient)
                        .environment(appState)
                }
            }
            .onChange(of: appState.error?.localizedDescription) { _, newDescription in
                if newDescription != nil && !hasUserDismissedError {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showingErrorAlert = true
                    }

                    // Auto-dismiss after 4 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        withAnimation {
                            showingErrorAlert = false
                            hasUserDismissedError = true
                        }
                    }
                } else if newDescription == nil {
                    // Reset on successful load (no error)
                    hasUserDismissedError = false
                    showingErrorAlert = false
                }
            }
        }
    }

    @ViewBuilder
    private func errorBanner(_ error: Error) -> some View {
        if #available(iOS 26.0, *) {
            HStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Network Error")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(errorMessage(from: error))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    HapticManager.buttonPress()
                    withAnimation {
                        showingErrorAlert = false
                        hasUserDismissedError = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        } else {
            HStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Network Error")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(errorMessage(from: error))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    HapticManager.buttonPress()
                    withAnimation {
                        showingErrorAlert = false
                        hasUserDismissedError = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    private func errorMessage(from error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? "Network request failed"
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "No internet connection"
            case .timedOut:
                return "Request timed out"
            case .cancelled:
                return "Request was cancelled"
            default:
                return "Network error occurred"
            }
        }
        return error.localizedDescription
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "car.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(appState.selectedDevice == nil ? "No Device Selected" : "No Drives Yet")
                    .font(.title2.bold())

                Text(
                    appState.selectedDevice == nil
                        ? "Select a device to view drives here"
                        : "Start driving with openpilot to see your drives here"
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
    }
}

#Preview {
    DashboardView()
        .environment(AppState.shared)
}
