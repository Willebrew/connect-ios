//
//  RouteActionsSheet.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Route actions menu (share, preserve, etc.)
//

import SwiftUI

struct RouteActionsSheet: View {
    let route: Route
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        HapticManager.buttonPress()
                        copySegmentName()
                    } label: {
                        Label("Copy Segment Name", systemImage: "doc.on.doc")
                    }

                    if shareURL != nil {
                        Button {
                            HapticManager.buttonPress()
                            showingShareSheet = true
                        } label: {
                            Label("Share Route", systemImage: "square.and.arrow.up")
                        }
                    }

                    if let url = URL(string: "https://useradmin.comma.ai/?onebox=\(route.dongleId)/\(route.logId)") {
                        Button {
                            HapticManager.buttonPress()
                            UIApplication.shared.open(url)
                        } label: {
                            Label("View in Useradmin", systemImage: "safari")
                        }
                    }
                }

                // Only show public/preserve toggles for owned devices
                if let device = appState.selectedDevice, !device.isReadOnly {
                    Section {
                        Toggle(isOn: Binding(
                            get: { route.isPublic },
                            set: { newValue in
                                HapticManager.toggle()
                                Task {
                                    await togglePublic(to: newValue)
                                }
                            }
                        )) {
                            Label("Public Route", systemImage: "globe")
                        }

                        Toggle(isOn: Binding(
                            get: { route.isPreserved },
                            set: { newValue in
                                HapticManager.toggle()
                                Task {
                                    await togglePreserved(to: newValue)
                                }
                            }
                        )) {
                            Label("Preserve Route", systemImage: "pin")
                        }
                    } footer: {
                        Text("Preserved routes won't be automatically deleted. Limit: \(appState.selectedDevice?.prime == true ? "100" : "10") routes")
                    }
                }
            }
            .navigationTitle("Route Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        HapticManager.buttonPress()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private var shareURL: URL? {
        URL(string: "https://connect.comma.ai/\(route.dongleId)/\(route.logId)")
    }

    private func copySegmentName() {
        UIPasteboard.general.string = route.fullname
        dismiss()
    }

    private func togglePublic(to newValue: Bool) async {
        // Check if in demo mode
        if AuthService.shared.isDemoMode {
            Logger.data.notice("Cannot modify route public status in demo mode")
            HapticManager.actionError()
            return
        }

        let previous = route.isPublic
        route.isPublic = newValue

        do {
            try await appState.apiClient.setRoutePublic(fullname: route.fullname, isPublic: newValue)
        } catch {
            await MainActor.run {
                route.isPublic = previous
            }
            Logger.data.error("Failed to toggle public status", error: error)
        }
    }

    private func togglePreserved(to newValue: Bool) async {
        // Check if in demo mode
        if AuthService.shared.isDemoMode {
            Logger.data.notice("Cannot modify route preserved status in demo mode")
            HapticManager.actionError()
            return
        }

        let previous = route.isPreserved

        await MainActor.run {
            route.isPreserved = newValue
        }

        do {
            try await appState.apiClient.setRoutePreserved(fullname: route.fullname, preserved: newValue)
        } catch {
            await MainActor.run {
                route.isPreserved = previous
            }
            Logger.data.error("Failed to toggle preserved status", error: error)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}
