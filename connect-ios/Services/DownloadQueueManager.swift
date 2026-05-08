//
//  DownloadQueueManager.swift
//  connect-ios
//
//  Created by Will Killebrew on 1/21/26.
//
//  Manages video download queue with background processing and notifications

import Foundation
import UserNotifications
import Combine
import os

/// Manages a queue of video download/export tasks with notification support
@Observable
final class DownloadQueueManager {
    static let shared = DownloadQueueManager()
    
    // Queue state
    private(set) var queuedItems: [DownloadQueueItem] = []
    private(set) var activeItem: DownloadQueueItem?
    private(set) var completedItems: [DownloadQueueItem] = []
    
    // Services
    private let videoExportService = VideoExportService.shared
    private let photosSaveService = PhotosSaveService.shared
    
    // Processing state
    private(set) var isProcessing = false
    private var processingTask: Task<Void, Never>?
    
    // Persistence
    private let queueKey = "download_queue"
    
    private init() {
        loadPersistedQueue()
        Task {
            await requestNotificationPermission()
        }
    }
    
    // MARK: - Queue Item Types
    
    struct DownloadQueueItem: Identifiable, Codable {
        let id: UUID
        let routeFullname: String
        let routeDisplayName: String
        let camera: CameraAngleOption
        let quality: QualityOption
        let range: RangeOption
        let streamURL: URL  // The actual HLS stream URL to download
        var status: Status
        var progress: Double
        var errorMessage: String?
        let createdAt: Date
        var completedAt: Date?
        var outputPath: String?
        
        enum Status: String, Codable {
            case queued
            case downloading
            case converting
            case waitingForUpload
            case savingToPhotos
            case completed
            case failed
            case cancelled
            
            var displayName: String {
                switch self {
                case .queued: return "Queued"
                case .downloading: return "Downloading..."
                case .converting: return "Converting..."
                case .waitingForUpload: return "Waiting for device..."
                case .savingToPhotos: return "Saving to Photos..."
                case .completed: return "Completed"
                case .failed: return "Failed"
                case .cancelled: return "Cancelled"
                }
            }
        }
        
        enum CameraAngleOption: String, Codable, CaseIterable {
            case road
            case driver
            case wide
            
            var displayName: String {
                switch self {
                case .road: return "Road Camera"
                case .driver: return "Driver Camera"
                case .wide: return "Wide Camera"
                }
            }
            
            var iconName: String {
                switch self {
                case .road: return "car"
                case .driver: return "person.fill"
                case .wide: return "camera.aperture"
                }
            }
            
            var toExportCamera: VideoExportService.CameraAngle {
                switch self {
                case .road: return .road
                case .driver: return .driver
                case .wide: return .wide
                }
            }
        }
        
        enum QualityOption: String, Codable {
            case standard
            case high
            
            var displayName: String {
                switch self {
                case .standard: return "Standard"
                case .high: return "High Quality"
                }
            }
            
            var description: String {
                switch self {
                case .standard: return "Faster download (~480p)"
                case .high: return "Full resolution (1080p)"
                }
            }
        }
        
        enum RangeOption: Codable, Equatable {
            case currentSegment(Int)
            case fullDrive
            
            var displayName: String {
                switch self {
                case .currentSegment(let num): return "Segment \(num)"
                case .fullDrive: return "Full Drive"
                }
            }
        }
        
        init(
            routeFullname: String,
            routeDisplayName: String,
            camera: CameraAngleOption,
            quality: QualityOption,
            range: RangeOption,
            streamURL: URL
        ) {
            self.id = UUID()
            self.routeFullname = routeFullname
            self.routeDisplayName = routeDisplayName
            self.camera = camera
            self.quality = quality
            self.range = range
            self.streamURL = streamURL
            self.status = .queued
            self.progress = 0
            self.createdAt = Date()
        }
    }
    
    // MARK: - Queue Management
    
    /// Adds a new item to the download queue
    @MainActor
    func enqueue(
        routeFullname: String,
        routeDisplayName: String,
        camera: DownloadQueueItem.CameraAngleOption,
        quality: DownloadQueueItem.QualityOption,
        range: DownloadQueueItem.RangeOption,
        streamURL: URL
    ) -> DownloadQueueItem {
        let item = DownloadQueueItem(
            routeFullname: routeFullname,
            routeDisplayName: routeDisplayName,
            camera: camera,
            quality: quality,
            range: range,
            streamURL: streamURL
        )
        
        queuedItems.append(item)
        persistQueue()
        
        Logger.data.debug("Enqueued download: \(item.routeDisplayName)")
        
        // Start processing if not already
        if !isProcessing {
            startProcessing()
        }
        
        return item
    }
    
    /// Cancels a queued item
    @MainActor
    func cancel(itemId: UUID) {
        if let index = queuedItems.firstIndex(where: { $0.id == itemId }) {
            var item = queuedItems.remove(at: index)
            item.status = .cancelled
            completedItems.append(item)
        } else if activeItem?.id == itemId {
            videoExportService.cancelExport()
            var item = activeItem!
            item.status = .cancelled
            completedItems.append(item)
            activeItem = nil
        }
        
        persistQueue()
    }
    
    /// Removes a completed item from history
    @MainActor
    func removeCompletedItem(itemId: UUID) {
        completedItems.removeAll { $0.id == itemId }
        persistQueue()
    }
    
    /// Clears all completed items
    @MainActor
    func clearCompleted() {
        completedItems.removeAll()
        persistQueue()
    }
    
    /// Retries a failed item
    @MainActor
    func retry(itemId: UUID) {
        if let index = completedItems.firstIndex(where: { $0.id == itemId && $0.status == .failed }) {
            var item = completedItems.remove(at: index)
            item.status = .queued
            item.progress = 0
            item.errorMessage = nil
            queuedItems.append(item)
            
            if !isProcessing {
                startProcessing()
            }
        }
        
        persistQueue()
    }
    
    // MARK: - Processing
    
    private func startProcessing() {
        guard !isProcessing else { return }
        
        processingTask = Task {
            await processQueue()
        }
    }
    
    @MainActor
    private func processQueue() async {
        isProcessing = true
        
        while !queuedItems.isEmpty {
            guard !Task.isCancelled else { break }
            
            // Get next item
            var item = queuedItems.removeFirst()
            item.status = .downloading
            activeItem = item
            persistQueue()
            
            do {
                // Process the download
                let outputURL = try await processItem(item)
                
                // Save to Photos
                item.status = .savingToPhotos
                activeItem = item
                
                let identifier = try await photosSaveService.saveAndCleanup(outputURL)
                
                // Mark complete
                item.status = .completed
                item.progress = 1.0
                item.completedAt = Date()
                item.outputPath = identifier
                
                completedItems.insert(item, at: 0)
                activeItem = nil
                
                // Send notification
                await sendCompletionNotification(for: item)
                
                Logger.data.debug("Download completed: \(item.routeDisplayName)")
                
            } catch {
                Logger.data.error("Download failed: \(item.routeDisplayName)", error: error)
                
                item.status = .failed
                item.errorMessage = error.localizedDescription
                completedItems.insert(item, at: 0)
                activeItem = nil
                
                // Send failure notification
                await sendFailureNotification(for: item, error: error)
            }
            
            persistQueue()
        }
        
        isProcessing = false
    }
    
    @MainActor
    private func processItem(_ item: DownloadQueueItem) async throws -> URL {
        // Use the pre-built stream URL from the queue item
        let streamURL = item.streamURL
        
        Logger.data.debug("Processing download from: \(streamURL.absoluteString)")
        
        // Update status
        var updatedItem = item
        updatedItem.status = .converting
        activeItem = updatedItem
        
        // Export to MP4
        let outputName = generateOutputName(for: item)
        let outputURL = try await videoExportService.exportHLSToMP4(
            streamURL: streamURL,
            outputName: outputName
        )
        
        return outputURL
    }
    
    private func generateOutputName(for item: DownloadQueueItem) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        
        let routePart = item.routeFullname
            .replacingOccurrences(of: "|", with: "_")
            .replacingOccurrences(of: "--", with: "_")
        
        let cameraPart = item.camera.rawValue
        let rangePart: String
        switch item.range {
        case .currentSegment(let num): rangePart = "seg\(num)"
        case .fullDrive: rangePart = "full"
        }
        
        return "\(routePart)_\(cameraPart)_\(rangePart)_\(dateString)"
    }
    
    // MARK: - Notifications
    
    private func requestNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            
            if granted {
                Logger.data.debug("Notification permission granted")
            }
        } catch {
            Logger.data.error("Failed to request notification permission", error: error)
        }
    }
    
    private func sendCompletionNotification(for item: DownloadQueueItem) async {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = "\(item.routeDisplayName) has been saved to Photos"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: item.id.uuidString,
            content: content,
            trigger: nil
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Logger.data.error("Failed to send notification", error: error)
        }
    }
    
    private func sendFailureNotification(for item: DownloadQueueItem, error: Error) async {
        let content = UNMutableNotificationContent()
        content.title = "Download Failed"
        content.body = "\(item.routeDisplayName): \(error.localizedDescription)"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: item.id.uuidString,
            content: content,
            trigger: nil
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Logger.data.error("Failed to send notification", error: error)
        }
    }
    
    // MARK: - Persistence
    
    private func persistQueue() {
        do {
            let data = try JSONEncoder().encode(queuedItems + completedItems)
            UserDefaults.standard.set(data, forKey: queueKey)
        } catch {
            Logger.data.error("Failed to persist download queue", error: error)
        }
    }
    
    private func loadPersistedQueue() {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return }
        
        do {
            let items = try JSONDecoder().decode([DownloadQueueItem].self, from: data)
            
            for item in items {
                switch item.status {
                case .queued, .downloading, .converting, .waitingForUpload, .savingToPhotos:
                    var resetItem = item
                    resetItem.status = .queued
                    resetItem.progress = 0
                    queuedItems.append(resetItem)
                case .completed, .failed, .cancelled:
                    completedItems.append(item)
                }
            }
            
            // Start processing if there are queued items
            if !queuedItems.isEmpty {
                startProcessing()
            }
        } catch {
            Logger.data.error("Failed to load persisted queue", error: error)
        }
    }
    
    // MARK: - Status Helpers
    
    var hasActiveDownloads: Bool {
        activeItem != nil || !queuedItems.isEmpty
    }
    
    var totalProgress: Double {
        guard hasActiveDownloads else { return 0 }
        
        let activeProgress = activeItem?.progress ?? 0
        let queuedCount = queuedItems.count
        let totalItems = queuedCount + (activeItem != nil ? 1 : 0)
        
        guard totalItems > 0 else { return 0 }
        
        return activeProgress / Double(totalItems)
    }
}
