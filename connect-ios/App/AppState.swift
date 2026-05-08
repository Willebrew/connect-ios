//
//  AppState.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Global app state management
//

import Foundation
import SwiftUI
import UIKit
import os
import WidgetKit

struct RouteLocations {
    var start: Location?
    var end: Location?
}

@Observable
final class AppState {
    static let shared = AppState()

    // Services
    let authService = AuthService.shared
    var apiClient: APIClient

    // App state
    var selectedDeviceId: String?
    var devices: [Device] = []
    var routes: [Route] = []
    var isLoadingDevices = false
    var isLoadingRoutes = false
    var hasMoreRoutes = true
    var error: Error?
    
    // Coordinate cache for map previews (keyed by route fullname)
    // This is observable by SwiftUI, unlike @Transient properties on Route
    var routeCoordinatesCache: [String: [Int: Coordinate]] = [:]

    // Route summary cache for timeline + locations (keyed by route fullname)
    var routeEventsCache: [String: [DriveEvent]] = [:]
    var routeLocationsCache: [String: RouteLocations] = [:]
    
    // Track ongoing coordinate requests to avoid duplicates
    private var activeCoordinateRequests: Set<String> = []

    // Snapshot cache for drive card map previews (not observable, accessed directly)
    // Using NSCache for automatic memory management
    let mapSnapshotCache = NSCache<NSString, UIImage>()

    // Settings
    var distanceUnit: AppConstants.DistanceUnit = .miles
    var timeFilterDays = AppConstants.defaultTimeFilterDays

    // Pagination
    private var currentRoutesLimit = AppConstants.defaultRoutesLimit

    // Computed auth state
    var isAuthenticated: Bool {
        authService.isAuthenticated
    }

    private init() {
        // Always initialize with ProductionAPIClient
        // Demo mode now uses a real JWT token instead of fake data
        apiClient = ProductionAPIClient()

        loadSettings()
        loadSelectedDevice()

        // Set up unauthorized handler
        let productionClient = apiClient as! ProductionAPIClient
        productionClient.setUnauthorizedHandler { [weak self] in
            DispatchQueue.main.async {
                Logger.auth.error("Unauthorized access detected - logging out")
                self?.handleUnauthorized()
            }
        }

        // If we have a saved token, set it on the client
        if let savedToken = authService.currentToken {
            productionClient.setAuthToken(savedToken)
            Logger.auth.debug("Restored saved auth token on app launch")

            // Fetch profile if we don't have it saved
            if authService.currentProfile == nil {
                Task { @MainActor in
                    do {
                        let profile = try await productionClient.getProfile()
                        authService.setProfile(profile)
                        Logger.auth.debug("Fetched user profile on app launch")
                    } catch {
                        Logger.auth.error("Failed to fetch profile on app launch", error: error)
                    }
                }
            }
        }
    }

    // MARK: - Auth

    /// Handles unauthorized access (401 errors)
    @MainActor
    func handleUnauthorized() {
        authService.logout()
        clearUserData()
    }

    /// Logs out the user
    @MainActor
    func logout() {
        authService.logout()
        clearUserData()
    }

    /// Clears all user-specific data from memory and persistence
    private func clearUserData() {
        // Clear in-memory state
        devices = []
        routes = []
        selectedDeviceId = nil
        error = nil
        hasMoreRoutes = true

        // Clear persisted device selection
        UserDefaults.standard.removeObject(forKey: "selected_device_id")

        // Clear widget data for all devices and mark as logged out
        WidgetDataStore.removeAllDeviceData()
        WidgetDataStore.setLoggedIn(false)
        WidgetCenter.shared.reloadAllTimelines()

        // Don't switch to demo client on logout - user may log back in with real account
        // If user chooses demo mode, switchToDemo() will handle the client switch
    }

    // MARK: - Devices

    private var loadDevicesTask: Task<Void, Never>?

    @MainActor
    func loadDevices() async {
        // If already loading, wait for that task to complete instead of starting a new one
        if let existingTask = loadDevicesTask {
            Logger.data.info("⏳ loadDevices() already in progress, waiting...")
            await existingTask.value
            return
        }

        Logger.data.debug("Loading devices (authenticated: \(authService.isAuthenticated))")

        let task = Task { @MainActor in
            isLoadingDevices = true
            error = nil

            do {
                devices = try await apiClient.listDevices()
                Logger.data.debug("Loaded \(devices.count) devices")

                // Check if currently selected device still exists
                if let currentSelection = selectedDeviceId {
                    if !devices.contains(where: { $0.dongleId == currentSelection }) {
                        // Selected device no longer exists (was unpaired) - clear selection
                        selectedDeviceId = nil
                        UserDefaults.standard.removeObject(forKey: "selected_device_id")
                        routes = [] // Clear routes from unpaired device
                        Logger.data.info("Selected device was unpaired - cleared selection")
                    }
                }

                // Auto-select first device if none selected
                if selectedDeviceId == nil, let firstDevice = devices.first {
                    Logger.data.debug("Auto-selecting first device: \(firstDevice.dongleId)")
                    selectedDeviceId = firstDevice.dongleId
                    saveSelectedDevice()
                } else {
                    Logger.data.debug("Device already selected: \(selectedDeviceId ?? "none")")
                }
            } catch {
                // Don't show error banner for permission denied or cancellation errors
                if !error.isPermissionDenied && !error.isCancellationError {
                    self.error = error
                }
                // Only log non-cancellation errors
                if !error.isCancellationError {
                    Logger.data.error("Failed to load devices", error: error)
                }
            }

            isLoadingDevices = false
            Logger.data.debug("Finished loading devices: \(devices.count) found")
        }

        loadDevicesTask = task
        await task.value
        loadDevicesTask = nil
    }

    @MainActor
    func selectDevice(_ deviceId: String) {
        selectedDeviceId = deviceId
        saveSelectedDevice()
        routes = [] // Clear routes when switching devices
    }

    @MainActor
    func updateDevice(_ updatedDevice: Device) {
        if let index = devices.firstIndex(where: { $0.dongleId == updatedDevice.dongleId }) {
            devices[index] = updatedDevice
        }
    }
    var selectedDevice: Device? {
        devices.first { $0.dongleId == selectedDeviceId }
    }

    // MARK: - Routes

    private var lastRefreshTime: Date?
    private let minRefreshInterval: TimeInterval = 2.0 // Minimum 2 seconds between refreshes

    @MainActor
    func loadRoutes() async {
        Logger.data.debug("Loading routes (authenticated: \(authService.isAuthenticated), device: \(selectedDeviceId ?? "none"))")
        guard authService.isAuthenticated else {
            return
        }
        guard let deviceId = selectedDeviceId else {
            return
        }

        // Debounce: prevent rapid successive refreshes
        if let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < minRefreshInterval {
            Logger.data.debug("Skipping refresh - too soon after last refresh")
            return
        }
        lastRefreshTime = Date()

        // Reset pagination limit on initial load
        currentRoutesLimit = AppConstants.defaultRoutesLimit

        isLoadingRoutes = true
        error = nil
        Logger.data.debug("Fetching routes for device \(deviceId) (\(timeFilterDays) days)")

        var currentFilterDays = timeFilterDays
        var fetchedRoutes: [Route] = []

        let maxRetries = 3
        var retryCount = 0

        while true {
            let range = dateRange(for: currentFilterDays)
            do {
                fetchedRoutes = try await apiClient.fetchRoutes(
                    dongleId: deviceId,
                    start: range.start,
                    end: range.end,
                    limit: currentRoutesLimit
                )
            } catch {
                if error.isCancellationError, retryCount < maxRetries {
                    retryCount += 1
                    Logger.data.debug("Route load cancelled (attempt \(retryCount) of \(maxRetries))")
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    continue
                }
                // Don't show error banner for permission denied or cancellation
                if !error.isPermissionDenied && !error.isCancellationError {
                    self.error = error
                }
                // Only log non-cancellation errors
                if !error.isCancellationError {
                    Logger.data.error("Failed to load routes", error: error)
                }
                isLoadingRoutes = false
                // Don't update routes on error - preserve existing data
                return
            }

            if !fetchedRoutes.isEmpty || currentFilterDays >= AppConstants.maxTimeFilterDays {
                break
            }

            let expanded = min(currentFilterDays * 2, AppConstants.maxTimeFilterDays)
            Logger.data.debug("No drives found for last \(currentFilterDays) days – expanding filter to \(expanded) days")
            currentFilterDays = expanded
        }

        // Preserve loaded data (events, coords, etc.) from existing routes
        let existingRoutesMap = Dictionary(uniqueKeysWithValues: routes.map { ($0.fullname, $0) })
        for newRoute in fetchedRoutes {
            if let existingRoute = existingRoutesMap[newRoute.fullname] {
                // Preserve cached data from existing route
                newRoute.events = existingRoute.events
                newRoute.driveCoords = existingRoute.driveCoords
                newRoute.startLocation = existingRoute.startLocation
                newRoute.endLocation = existingRoute.endLocation
                newRoute.videoStartOffset = existingRoute.videoStartOffset
                newRoute.startLat = existingRoute.startLat
                newRoute.startLng = existingRoute.startLng

                if let existingEvents = existingRoute.events {
                    routeEventsCache[newRoute.fullname] = existingEvents
                }

                if existingRoute.startLocation != nil || existingRoute.endLocation != nil {
                    routeLocationsCache[newRoute.fullname] = RouteLocations(
                        start: existingRoute.startLocation,
                        end: existingRoute.endLocation
                    )
                }
            }

            if let cachedEvents = routeEventsCache[newRoute.fullname] {
                newRoute.events = cachedEvents
            }

            if let cachedLocations = routeLocationsCache[newRoute.fullname] {
                newRoute.startLocation = cachedLocations.start
                newRoute.endLocation = cachedLocations.end
            }
        }

        // Update UI immediately with routes
        routes = fetchedRoutes
        isLoadingRoutes = false

        // Check if there are more routes to load based on the fetch size
        hasMoreRoutes = fetchedRoutes.count >= currentRoutesLimit

        if currentFilterDays != timeFilterDays {
            timeFilterDays = currentFilterDays
            saveSettings()
        }

        Logger.data.debug("Loaded \(routes.count) routes (hasMore: \(hasMoreRoutes))")

        // Lazy load timeline data in background (non-blocking)
        // Only preload first 5 routes instead of 15
        let routesToPreload = Array(fetchedRoutes.prefix(5))
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            Logger.data.debug("Background preloading timeline data for \(routesToPreload.count) routes")
            
            // Load sequentially to avoid overwhelming the network
            for route in routesToPreload {
                // Check if route still needs data
                if route.events == nil || route.startLocation == nil {
                    await self.preloadRouteSummaryData(for: route)
                }
            }
            Logger.data.debug("Background timeline preload complete")
        }
    }

    @MainActor
    func loadMoreRoutes() async {
        guard authService.isAuthenticated else { return }
        guard let deviceId = selectedDeviceId, !isLoadingRoutes else { return }

        // Check if we already have all routes
        if routes.count < currentRoutesLimit {
            Logger.data.debug("All routes already loaded (\(routes.count) < \(currentRoutesLimit))")
            hasMoreRoutes = false
            return
        }

        // Increase limit by 8 (matching initial load size) and refetch
        currentRoutesLimit += 8
        Logger.data.debug("Loading more routes with increased limit: \(currentRoutesLimit)")

        isLoadingRoutes = true
        error = nil

        let maxRetries = 3
        var retryCount = 0
        var fetchedRoutes: [Route] = []

        while true {
            let range = dateRange(for: timeFilterDays)
            do {
                fetchedRoutes = try await apiClient.fetchRoutes(
                    dongleId: deviceId,
                    start: range.start,
                    end: range.end,
                    limit: currentRoutesLimit
                )

                // Preserve loaded data from existing routes
                let existingRoutesMap = Dictionary(uniqueKeysWithValues: routes.map { ($0.fullname, $0) })
                for newRoute in fetchedRoutes {
                    if let existingRoute = existingRoutesMap[newRoute.fullname] {
                        // Preserve cached data from existing route
                        newRoute.events = existingRoute.events
                        newRoute.driveCoords = existingRoute.driveCoords
                        newRoute.startLocation = existingRoute.startLocation
                        newRoute.endLocation = existingRoute.endLocation
                        newRoute.videoStartOffset = existingRoute.videoStartOffset
                        newRoute.startLat = existingRoute.startLat
                        newRoute.startLng = existingRoute.startLng

                        if let existingEvents = existingRoute.events {
                            routeEventsCache[newRoute.fullname] = existingEvents
                        }

                        if existingRoute.startLocation != nil || existingRoute.endLocation != nil {
                            routeLocationsCache[newRoute.fullname] = RouteLocations(
                                start: existingRoute.startLocation,
                                end: existingRoute.endLocation
                            )
                        }
                    }

                    if let cachedEvents = routeEventsCache[newRoute.fullname] {
                        newRoute.events = cachedEvents
                    }

                    if let cachedLocations = routeLocationsCache[newRoute.fullname] {
                        newRoute.startLocation = cachedLocations.start
                        newRoute.endLocation = cachedLocations.end
                    }
                }

                // Replace routes array with new fetch (includes all previous + new)
                routes = fetchedRoutes

                // If we got fewer routes than the limit, there are no more to load
                hasMoreRoutes = fetchedRoutes.count >= currentRoutesLimit

                Logger.data.debug("Loaded \(routes.count) total routes (hasMore: \(hasMoreRoutes))")

                // Preload timeline data for newly visible routes (last 8) after UI updates
                let newlyVisibleRoutes = Array(fetchedRoutes.suffix(8))
                Task.detached(priority: .utility) { [weak self] in
                    guard let self = self else { return }
                    for route in newlyVisibleRoutes {
                        if route.events == nil || route.startLocation == nil {
                            await self.preloadRouteSummaryData(for: route)
                        }
                    }
                }

                break
            } catch {
                if error.isCancellationError, retryCount < maxRetries {
                    retryCount += 1
                    Logger.data.debug("Load more routes cancelled (attempt \(retryCount) of \(maxRetries))")
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    continue
                }
                // Don't show error banner for permission denied or cancellation
                if !error.isPermissionDenied && !error.isCancellationError {
                    self.error = error
                }
                // Only log non-cancellation errors
                if !error.isCancellationError {
                    Logger.data.error("Failed to load more routes", error: error)
                }
                break
            }
        }
        isLoadingRoutes = false
    }

    // MARK: - Route Data Hydration

    @MainActor
    func preloadRouteSummaryData(for route: Route) async {
        var updated = false

        Logger.data.debug("Preloading data for \(route.fullname)")

        if route.events == nil {
            do {
                let events = try await apiClient.fetchRouteEvents(route: route)
                Logger.data.debug("Fetched \(events.count) events for \(route.fullname)")
                route.events = events
                routeEventsCache[route.fullname] = events
                updated = true
            } catch {
                if !error.isCancellationError {
                    Logger.data.error("Failed to fetch events for \(route.fullname)", error: error)
                }
            }
        } else {
            // Events already loaded, skip
        }

        if route.startLocation == nil || route.endLocation == nil {
            Logger.data.debug("Fetching locations for \(route.fullname)")
            await ensureLocations(for: route, fallbackToDriveCoords: false)
            routeLocationsCache[route.fullname] = RouteLocations(
                start: route.startLocation,
                end: route.endLocation
            )
            updated = true
        }

        if !updated {
            // Route already hydrated
        }
    }

    /// Load drive coordinates for map preview - called lazily from card view
    /// Uses a fire-and-forget pattern to avoid blocking refresh
    func loadRouteCoordinatesInBackground(for route: Route) {
        let routeName = route.fullname
        
        // Already cached or loading
        guard routeCoordinatesCache[routeName] == nil else { return }
        guard !activeCoordinateRequests.contains(routeName) else { return }
        guard route.driveCoords == nil else {
            // Already on route, copy to cache
            if let coords = route.driveCoords {
                routeCoordinatesCache[routeName] = coords
            }
            return
        }
        
        // Mark as loading
        activeCoordinateRequests.insert(routeName)
        
        // Fire and forget - don't await
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            do {
                let coords = try await self.apiClient.fetchDriveCoordinates(route: route)
                await MainActor.run {
                    route.driveCoords = coords
                    self.routeCoordinatesCache[routeName] = coords
                    self.activeCoordinateRequests.remove(routeName)
                }
            } catch {
                // Silent fail - map preview will use start/end fallback
                await MainActor.run {
                    self.activeCoordinateRequests.remove(routeName)
                    if !error.isCancellationError {
                        Logger.data.debug("Failed to fetch coords for card preview: \(routeName)")
                    }
                }
            }
        }
    }
    
    /// Load drive coordinates for map preview - awaitable version for detail view
    @MainActor
    func loadRouteCoordinates(for route: Route) async {
        guard route.driveCoords == nil else { return }

        do {
            let coords = try await apiClient.fetchDriveCoordinates(route: route)
            route.driveCoords = coords
            routeCoordinatesCache[route.fullname] = coords
        } catch {
            // Silent fail - map preview will use start/end fallback
            if !error.isCancellationError {
                Logger.data.debug("Failed to fetch coords for card preview: \(route.fullname)")
            }
        }
    }

    @MainActor
    func preloadRouteDetailData(for route: Route) async {
        // Load summary data and coordinates in parallel for faster loading
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Load summary data (events, locations)
            group.addTask { @MainActor in
                await self.preloadRouteSummaryData(for: route)
            }
            
            // Task 2: Load drive coordinates
            group.addTask { @MainActor in
                if route.driveCoords == nil {
                    do {
                        let coords = try await self.apiClient.fetchDriveCoordinates(route: route)
                        route.driveCoords = coords
                    } catch {
                        if !error.isCancellationError {
                            Logger.data.error("Failed to fetch drive coordinates", error: error)
                        }
                    }
                }
            }
        }

        // After both complete, ensure locations using coords if needed
        if route.startLocation == nil || route.endLocation == nil {
            await ensureLocations(for: route, fallbackToDriveCoords: true)
        }
    }

    @MainActor
    private func ensureLocations(for route: Route, fallbackToDriveCoords: Bool) async {
        if route.startLocation == nil {
            if let lat = route.startLat, let lng = route.startLng {
                if let location = try? await apiClient.reverseGeocode(latitude: lat, longitude: lng) {
                    route.startLocation = location
                }
            } else if fallbackToDriveCoords, let coord = coordinate(from: route.driveCoords, useFirst: true) {
                if let location = try? await apiClient.reverseGeocode(latitude: coord.latitude, longitude: coord.longitude) {
                    route.startLocation = location
                }
            }
        }

        if route.endLocation == nil {
            if let lat = route.endLat, let lng = route.endLng {
                if let location = try? await apiClient.reverseGeocode(latitude: lat, longitude: lng) {
                    route.endLocation = location
                }
            } else if fallbackToDriveCoords, let coord = coordinate(from: route.driveCoords, useFirst: false) {
                if let location = try? await apiClient.reverseGeocode(latitude: coord.latitude, longitude: coord.longitude) {
                    route.endLocation = location
                }
            }
        }
    }

    private func coordinate(from coords: [Int: Coordinate]?, useFirst: Bool) -> Coordinate? {
        guard let coords else { return nil }
        guard let key = useFirst ? coords.keys.min() : coords.keys.max() else {
            return nil
        }
        return coords[key]
    }

    // MARK: - Persistence

    private func loadSettings() {
        if let unitString = UserDefaults.standard.string(forKey: "distance_unit"),
           let unit = AppConstants.DistanceUnit(rawValue: unitString) {
            distanceUnit = unit
        }
        let savedDays = UserDefaults.standard.integer(forKey: "time_filter_days")
        if savedDays > 0 {
            timeFilterDays = savedDays
        }

        // Sync distance unit to shared container for widget
        WidgetDataStore.saveDistanceUnit(distanceUnit.rawValue)
    }

    private func loadSelectedDevice() {
        selectedDeviceId = UserDefaults.standard.string(forKey: "selected_device_id")
    }

    private func saveSelectedDevice() {
        UserDefaults.standard.set(selectedDeviceId, forKey: "selected_device_id")
    }

    func saveSettings() {
        UserDefaults.standard.set(distanceUnit.rawValue, forKey: "distance_unit")
        UserDefaults.standard.set(timeFilterDays, forKey: "time_filter_days")

        // Also save to shared container for widget
        WidgetDataStore.saveDistanceUnit(distanceUnit.rawValue)

        // Reload widgets to reflect new settings
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func dateRange(for days: Int) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()

        let nextHourBase = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        let nextHour = calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour], from: nextHourBase)
        ) ?? nextHourBase

        let start = calendar.date(byAdding: .day, value: -days, to: nextHour) ?? now
        return (start, nextHour)
    }
}
