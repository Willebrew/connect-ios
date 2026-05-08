//
//  DeviceLocatorView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Full-screen device locator map
//

import SwiftUI
import MapKit
import Combine

struct DeviceLocatorView: View {
    @Environment(AppState.self) private var appState
    @State private var locationService: LocationService
    @State private var selectedDevice: DeviceLocation?
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
    )
    @StateObject private var locationManager = UserLocationManager()
    @State private var dragOffset: CGFloat = 0
    @State private var selectedDeviceTimestamp: String = ""
    @State private var shouldCenterOnUserLocation = false
    @State private var hasInitiallyLoaded = false
    @State private var showingReadOnlyAlert = false
    @State private var readOnlyDeviceName = ""

    init(apiClient: APIClient) {
        self._locationService = State(initialValue: LocationService(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Map view
                Map(position: $cameraPosition) {
                    // User location
                    UserAnnotation()

                    ForEach(Array(locationService.deviceLocations.values)) { location in
                        Annotation(deviceName(for: location.dongleId), coordinate: location.coordinate) {
                            DeviceMapPin(location: location)
                                .onTapGesture {
                                    HapticManager.deviceSelection()
                                    // Offset camera south so device appears in visible area (above bottom sheet)
                                    let offsetCenter = CLLocationCoordinate2D(
                                        latitude: location.latitude - 0.012,
                                        longitude: location.longitude
                                    )
                                    let region = MKCoordinateRegion(
                                        center: offsetCenter,
                                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                                    )
                                    withAnimation(.smooth(duration: 0.8)) {
                                        cameraPosition = .region(region)
                                    }

                                    // Show device info sheet
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        selectedDeviceTimestamp = location.formattedTimestamp
                                        dragOffset = 0
                                        selectedDevice = location
                                    }
                                }
                        }

                        // Accuracy circle
                        MapCircle(center: location.coordinate, radius: location.accuracy)
                            .foregroundStyle(Color.themeGreen.opacity(0.2))
                            .stroke(Color.themeGreen, lineWidth: 1)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .safeAreaPadding(.top, 180)

                // Top gradient fade
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(0.7), .black.opacity(0.4), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .allowsHitTesting(false)
                    
                    Spacer()
                }

                // Quick navigation chips
                VStack {
                    Spacer()
                        .frame(height: 110) // Space for nav bar
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // My Location button
                            Button {
                                HapticManager.buttonPress()
                                centerOnUserLocation()
                            } label: {
                                if #available(iOS 26.0, *) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "location.fill")
                                            .font(.subheadline)
                                        Text("My Location")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .glassEffect(.regular, in: Capsule())
                                } else {
                                    HStack(spacing: 6) {
                                        Image(systemName: "location.fill")
                                            .font(.subheadline)
                                        Text("My Location")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: Capsule())
                                }
                            }

                            // Device buttons - show ALL devices
                            ForEach(appState.devices) { device in
                                Button {
                                    HapticManager.deviceSelection()
                                    handleDeviceTap(device)
                                } label: {
                                    let hasLocation = locationService.deviceLocations[device.dongleId] != nil

                                    if #available(iOS 26.0, *) {
                                        HStack(spacing: 6) {
                                            Image(systemName: hasLocation ? "car.fill" : "car")
                                                .font(.subheadline)
                                            Text(device.displayName)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                        }
                                        .foregroundStyle(hasLocation ? .white : .white.opacity(0.6))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .glassEffect(.regular, in: Capsule())
                                    } else {
                                        HStack(spacing: 6) {
                                            Image(systemName: hasLocation ? "car.fill" : "car")
                                                .font(.subheadline)
                                            Text(device.displayName)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                        }
                                        .foregroundStyle(hasLocation ? .white : .white.opacity(0.6))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(.ultraThinMaterial, in: Capsule())
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    Spacer()
                }

                // Error banner - suppress 403 errors (expected for read-only devices)
                // Only show non-permission errors
                if let error = locationService.lastError,
                   !error.contains("403") && !error.contains("permission") {
                    VStack {
                        Spacer()
                            .frame(height: 150) // Space below nav bar, notch, and device chip buttons

                        if #available(iOS 26.0, *) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.subheadline)
                            }
                            .padding()
                            .glassEffect()
                            .padding()
                        } else {
                            // Fallback on earlier versions
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.subheadline)
                            }
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding()
                        }
                        Spacer()
                    }
                }

                // Device info sheet
                if selectedDevice != nil {
                    VStack {
                        Spacer()
                        if #available(iOS 26.0, *) {
                            // iOS 26+ Liquid Glass implementation
                            ZStack(alignment: .topTrailing) {
                                DeviceLocationCard(
                                    location: selectedDevice!,
                                    deviceName: deviceName(for: selectedDevice!.dongleId),
                                    locationService: locationService,
                                    timestamp: selectedDeviceTimestamp,
                                    onClose: {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            dragOffset = 600
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            dragOffset = 0
                                            selectedDevice = nil
                                        }
                                    }
                                )
                            }
                            .padding()
                            .padding(.bottom, 20)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .padding()
                            .offset(y: dragOffset > 0 ? dragOffset : 0)
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                DragGesture()
                                    .onChanged { value in
                                        if value.translation.height > 0 {
                                            dragOffset = value.translation.height
                                        }
                                    }
                                    .onEnded { value in
                                        if value.translation.height > 150 {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                dragOffset = 0
                                                selectedDevice = nil
                                            }
                                        } else {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                                dragOffset = 0
                                            }
                                        }
                                    }
                            )
                        } else {
                            // Fallback on earlier versions
                            ZStack(alignment: .topTrailing) {
                                DeviceLocationCard(
                                    location: selectedDevice!,
                                    deviceName: deviceName(for: selectedDevice!.dongleId),
                                    locationService: locationService,
                                    timestamp: selectedDeviceTimestamp,
                                    onClose: {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            dragOffset = 600
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            dragOffset = 0
                                            selectedDevice = nil
                                        }
                                    }
                                )
                            }
                            .padding()
                            .padding(.bottom, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
                            .padding()
                            .offset(y: dragOffset > 0 ? dragOffset : 0)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if value.translation.height > 0 {
                                            dragOffset = value.translation.height
                                        }
                                    }
                                    .onEnded { value in
                                        if value.translation.height > 150 {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                dragOffset = 0
                                                selectedDevice = nil
                                            }
                                        } else {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                                dragOffset = 0
                                            }
                                        }
                                    }
                            )
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationTitle("Find Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        HapticManager.refresh()
                        Task {
                            await refreshLocations()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(locationService.isLoading)
                }
            }
            .task(priority: .userInitiated) {
                // Small delay to let UI settle before loading
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                await loadLocations()
            }
            .onChange(of: locationManager.lastLocation) { _, newLocation in
                // Auto-center on user location after permission is granted
                if shouldCenterOnUserLocation, let userLocation = newLocation {
                    shouldCenterOnUserLocation = false
                    animateToUserLocation(userLocation)
                }
            }
            .alert("Location Unavailable", isPresented: $showingReadOnlyAlert) {
                Button("OK", role: .cancel) {
                    HapticManager.buttonPress()
                }
            } message: {
                Text("You have read-only access to \(readOnlyDeviceName). Device location is only available to the device owner.")
            }
        }
    }

    private func deviceName(for dongleId: String) -> String {
        appState.devices.first(where: { $0.dongleId == dongleId })?.displayName ?? dongleId
    }

    private func loadLocations() async {
        await locationService.fetchAllLocations(devices: appState.devices)

        // Center map on devices only on first load
        if !hasInitiallyLoaded && !locationService.deviceLocations.isEmpty {
            centerMapOnDevices()
            hasInitiallyLoaded = true
        }
    }

    private func refreshLocations() async {
        await appState.loadDevices()
        await locationService.fetchAllLocations(devices: appState.devices)
        centerMapOnDevices()
    }

    private func centerMapOnDevices() {
        let locations = Array(locationService.deviceLocations.values)
        guard !locations.isEmpty else { return }

        if locations.count == 1 {
            // Single device - center on it
            let loc = locations[0]
            let region = MKCoordinateRegion(
                center: loc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            withAnimation(.easeInOut(duration: 0.3)) {
                cameraPosition = .region(region)
            }
        } else {
            // Multiple devices - fit all
            let lats = locations.map { $0.latitude }
            let lons = locations.map { $0.longitude }

            let minLat = lats.min() ?? 0
            let maxLat = lats.max() ?? 0
            let minLon = lons.min() ?? 0
            let maxLon = lons.max() ?? 0

            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )

            let span = MKCoordinateSpan(
                latitudeDelta: (maxLat - minLat) * 1.5,
                longitudeDelta: (maxLon - minLon) * 1.5
            )
            withAnimation(.easeInOut(duration: 0.3)) {
                cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
            }
        }
    }

    private func centerOnUserLocation() {
        // Always request fresh location
        locationManager.requestLocation()

        // If we already have a location, use it immediately
        // But also set flag to update when fresh location arrives
        if let userLocation = locationManager.lastLocation {
            animateToUserLocation(userLocation)
        }

        // Set flag to animate again when fresh location arrives
        // This ensures we always center on the most recent location
        shouldCenterOnUserLocation = true
    }

    private func animateToUserLocation(_ userLocation: CLLocation) {
        // Only offset camera if device info sheet is open, otherwise center directly
        let centerCoordinate: CLLocationCoordinate2D
        if selectedDevice != nil {
            // Offset camera south so user location appears above the bottom sheet
            centerCoordinate = CLLocationCoordinate2D(
                latitude: userLocation.coordinate.latitude - 0.012,
                longitude: userLocation.coordinate.longitude
            )
        } else {
            // No sheet open, center directly on user location
            centerCoordinate = userLocation.coordinate
        }

        let region = MKCoordinateRegion(
            center: centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        withAnimation(.smooth(duration: 0.8)) {
            cameraPosition = .region(region)
        }
    }

    private func handleDeviceTap(_ device: Device) {
        // Check if this device has location data
        if let location = locationService.deviceLocations[device.dongleId] {
            // Has location - center on it
            centerOnDevice(location)
        } else {
            // No location (read-only device) - show alert
            HapticManager.actionError()
            readOnlyDeviceName = device.displayName
            showingReadOnlyAlert = true
        }
    }

    private func centerOnDevice(_ location: DeviceLocation) {
        // Offset camera south so device appears in visible area (above bottom sheet)
        let offsetCenter = CLLocationCoordinate2D(
            latitude: location.latitude - 0.012,
            longitude: location.longitude
        )
        let region = MKCoordinateRegion(
            center: offsetCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        withAnimation(.smooth(duration: 0.8)) {
            cameraPosition = .region(region)
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            selectedDeviceTimestamp = location.formattedTimestamp
            dragOffset = 0
            selectedDevice = location
        }
    }
}

// User location manager
class UserLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func requestLocation() {
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.data.error("Location error", error: error)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}

struct DeviceMapPin: View {
    let location: DeviceLocation

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.themeGreen.gradient)
                .frame(width: 44, height: 44)
                .shadow(radius: 4)

            Image(systemName: "car.fill")
                .font(.title3)
                .foregroundStyle(.white)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct DeviceLocationCard: View {
    let location: DeviceLocation
    let deviceName: String
    let locationService: LocationService
    let timestamp: String

    let onClose: (() -> Void)?

    init(location: DeviceLocation, deviceName: String, locationService: LocationService, timestamp: String, onClose: (() -> Void)? = nil) {
        self.location = location
        self.deviceName = deviceName
        self.locationService = locationService
        self.timestamp = timestamp
        self.onClose = onClose
    }

    @State private var address: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deviceName)
                        .font(.headline)

                    Text(timestamp)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: {
                    HapticManager.buttonPress()
                    onClose?()
                }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }

            Divider()

            // Location details
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(
                    icon: "location.fill",
                    title: "Coordinates",
                    value: String(format: "%.6f, %.6f", location.latitude, location.longitude)
                )

                InfoRow(
                    icon: "mappin.circle.fill",
                    title: "Address",
                    value: address ?? "Loading..."
                )

                InfoRow(
                    icon: "scope",
                    title: "Accuracy",
                    value: String(format: "±%.0f meters", location.accuracy)
                )
            }

            // Actions
            HStack(spacing: 12) {
                Button {
                    HapticManager.buttonPress()
                    openInMaps()
                } label: {
                    if #available(iOS 26.0, *) {
                        Label("Open in Maps", systemImage: "map.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .glassEffect()
                    } else {
                        // Fallback on earlier versions
                        Label("Open in Maps", systemImage: "map.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.themeGreen.gradient, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                }

                if let url = shareURL {
                    ShareLink(item: url) {
                        if #available(iOS 26.0, *) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .frame(width: 50, height: 50)
                                .glassEffect()
                        } else {
                            // Fallback on earlier versions
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .frame(width: 50, height: 50)
                                .background(Color.themeGreen.gradient, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .padding()
        .task {
            address = await locationService.reverseGeocode(
                latitude: location.latitude,
                longitude: location.longitude
            )
        }
    }

    private var shareURL: URL? {
        let coordinate = location.coordinate
        let urlString = "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=\(deviceName)"
        return URL(string: urlString)
    }

    private func openInMaps() {
        let coordinate = location.coordinate
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = deviceName
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        ])
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.themeGreen)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.subheadline)
            }
        }
    }
}

#Preview {
    DeviceLocatorView(apiClient: ProductionAPIClient())
        .environment(AppState.shared)
}
