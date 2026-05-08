//
//  FileDownloadSheet.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/14/25.
//
//  File download interface for route segments - redesigned with Save to Photos as primary action

import SwiftUI
import UniformTypeIdentifiers
import os

struct FileDownloadSheet: View {
    let route: Route
    let currentSegment: Int?
    let apiClient: APIClient
    
    @State private var fileService: FileManagementService
    @State private var availableFiles: [FileType: [RouteFileEntry]] = [:]
    @State private var isLoading = true
    @State private var downloadingFiles: Set<String> = []
    @State private var advancedExpanded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var fileToExport: URL?
    @State private var exportFileName: String = ""

    init(route: Route, apiClient: APIClient, currentSegment: Int? = nil) {
        self.route = route
        self.apiClient = apiClient
        self.currentSegment = currentSegment
        let athenaService = AthenaService(apiClient: apiClient)
        self._fileService = State(initialValue: FileManagementService(apiClient: apiClient, athenaService: athenaService))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Primary: Save to Photos
                        saveToPhotosSection

                        // Active Downloads (if any)
                        activeDownloadsSection

                        // Advanced: Raw file downloads
                        advancedSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        HapticManager.buttonPress()
                        dismiss()
                    }
                }
            }
            .task {
                await loadAvailableFiles()
            }
            .fileExporter(
                isPresented: Binding(
                    get: { fileToExport != nil },
                    set: { if !$0 { fileToExport = nil } }
                ),
                document: fileToExport.map { DownloadedFile(fileURL: $0) },
                contentType: .data,
                defaultFilename: exportFileName
            ) { result in
                switch result {
                case .success:
                    Logger.data.debug("File exported successfully")
                case .failure(let error):
                    Logger.data.error("Failed to export file", error: error)
                }
            }
        }
    }
    
    // MARK: - Save to Photos Section
    
    private var saveToPhotosSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(Color.themeGreen)
                
                Text("Save to Photos")
                    .font(.title3.weight(.semibold))
                
                Spacer()
            }
            
            // Save to Photos content
            SaveToPhotosView(
                route: route,
                currentSegment: currentSegment,
                apiClient: apiClient
            )
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
    
    // MARK: - Active Downloads Section
    
    @ViewBuilder
    private var activeDownloadsSection: some View {
        let queueManager = DownloadQueueManager.shared
        
        if queueManager.hasActiveDownloads || !queueManager.completedItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundStyle(Color.themeGreen)
                    
                    Text("Download Queue")
                        .font(.headline)
                    
                    Spacer()
                    
                    if !queueManager.completedItems.isEmpty {
                        Button("Clear") {
                            HapticManager.buttonPress()
                            queueManager.clearCompleted()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                
                // Active item
                if let activeItem = queueManager.activeItem {
                    downloadQueueRow(activeItem, isActive: true)
                }
                
                // Queued items
                ForEach(queueManager.queuedItems) { item in
                    downloadQueueRow(item, isActive: false)
                }
                
                // Recent completed (limit to 3)
                ForEach(queueManager.completedItems.prefix(3)) { item in
                    downloadQueueRow(item, isActive: false)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func downloadQueueRow(_ item: DownloadQueueManager.DownloadQueueItem, isActive: Bool) -> some View {
        HStack {
            // Status indicator
            Group {
                switch item.status {
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                case .cancelled:
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                default:
                    if isActive {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.routeDisplayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(item.camera.displayName)
                    Text("\u{2022}")
                    Text(item.status.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Progress or action
            if isActive && item.progress > 0 {
                Text("\(Int(item.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if item.status == .failed {
                Button("Retry") {
                    HapticManager.buttonPress()
                    DownloadQueueManager.shared.retry(itemId: item.id)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.themeGreen)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Advanced Section
    
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Expandable header
            Button {
                HapticManager.buttonPress()
                withAnimation(.easeInOut(duration: 0.25)) {
                    advancedExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "folder")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    
                    Text("Advanced Options")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(advancedExpanded ? 90 : 0))
                }
                .padding()
            }
            .buttonStyle(.plain)
            
            if advancedExpanded {
                Divider()
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 16) {
                    // Description
                    Text("Download raw files in their original format. These files may not be directly playable on iOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    // Current segment files
                    if let segment = currentSegment {
                        currentSegmentFilesSection(segment: segment)
                    }
                    
                    // All segments link
                    allSegmentsLink
                    
                    // Upload request (for owned devices)
                    uploadRequestSection
                }
                .padding(.bottom)
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func currentSegmentFilesSection(segment: Int) -> some View {
        if isLoading {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding()
        } else {
            let segmentFiles = filesForSegment(segment)
            
            if segmentFiles.isEmpty {
                Text("No files available for this segment")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    Text("Current Segment (\(segment))")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    
                    ForEach(segmentFiles, id: \.fileType) { item in
                        FileDownloadRow(
                            fileType: item.fileType,
                            entry: item.entry,
                            isDownloading: downloadingFiles.contains(downloadKey(for: item.fileType, entry: item.entry)),
                            showSegmentNumber: false
                        ) {
                            await downloadFile(fileType: item.fileType, entry: item.entry)
                        }
                        .padding(.horizontal)
                        
                        if item.fileType != segmentFiles.last?.fileType {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }
    
    private var allSegmentsLink: some View {
        NavigationLink {
            AllSegmentsView(
                route: route,
                availableFiles: availableFiles,
                downloadingFiles: $downloadingFiles,
                onDownload: downloadFile
            )
        } label: {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.themeGreen)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse All Segments")
                        .font(.subheadline.weight(.medium))
                    
                    if !isLoading {
                        Text("\(uniqueSegmentCount) segments with files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var uploadRequestSection: some View {
        if let device = appState.selectedDevice, !device.isReadOnly {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                    .padding(.horizontal)
                
                Button {
                    HapticManager.buttonPress()
                    Task {
                        await requestUploadAll()
                    }
                } label: {
                    HStack {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundStyle(deviceIsOnline ? Color.themeGreen : .secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Request Device Upload")
                                .font(.subheadline.weight(.medium))
                            
                            Text(deviceIsOnline ? "Upload all files from device to cloud" : "Device is offline")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!deviceIsOnline)
                .opacity(deviceIsOnline ? 1.0 : 0.6)
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func filesForSegment(_ segment: Int) -> [(fileType: FileType, entry: RouteFileEntry)] {
        var result: [(fileType: FileType, entry: RouteFileEntry)] = []
        
        for fileType in FileType.allCases {
            if let entries = availableFiles[fileType],
               let entry = entries.first(where: { $0.segmentNumber == segment }) {
                result.append((fileType: fileType, entry: entry))
            }
        }
        
        return result
    }
    
    private var uniqueSegmentCount: Int {
        var segments = Set<Int>()
        for entries in availableFiles.values {
            for entry in entries {
                if let seg = entry.segmentNumber {
                    segments.insert(seg)
                }
            }
        }
        return segments.count
    }

    private func loadAvailableFiles() async {
        isLoading = true

        do {
            availableFiles = try await fileService.getAvailableFiles(route: route)
        } catch {
            Logger.data.error("Failed to load available files", error: error)
        }

        isLoading = false
    }

    private func downloadFile(fileType: FileType, entry: RouteFileEntry) async {
        let key = downloadKey(for: fileType, entry: entry)
        downloadingFiles.insert(key)

        do {
            let suggestedName = makeFileName(for: fileType, entry: entry)
            let localURL = try await fileService.downloadFile(url: entry.url, preferredName: suggestedName)
            await MainActor.run {
                exportFileName = suggestedName
                fileToExport = localURL
            }
        } catch {
            Logger.data.error("Failed to download file", error: error)
        }

        downloadingFiles.remove(key)
    }

    private func downloadKey(for fileType: FileType, entry: RouteFileEntry) -> String {
        "\(fileType.rawValue)-\(entry.id)"
    }

    private func makeFileName(for fileType: FileType, entry: RouteFileEntry) -> String {
        let segmentText = entry.segmentNumber.map { "--\($0)" } ?? ""
        return "\(route.fullname)\(segmentText)--\(entry.fileName)"
    }

    private var deviceIsOnline: Bool {
        appState.devices.first(where: { $0.dongleId == route.dongleId })?.isOnline ?? false
    }

    private func requestUploadAll() async {
        guard deviceIsOnline else {
            Logger.data.debug("Device is offline. Cannot request upload.")
            return
        }

        do {
            for fileType in FileType.allCases {
                try await fileService.requestUpload(dongleId: route.dongleId, route: route, fileType: fileType)
            }

            dismiss()
        } catch {
            Logger.data.error("Failed to request upload", error: error)
        }
    }
}

// MARK: - All Segments View

struct AllSegmentsView: View {
    let route: Route
    let availableFiles: [FileType: [RouteFileEntry]]
    @Binding var downloadingFiles: Set<String>
    let onDownload: (FileType, RouteFileEntry) async -> Void
    
    var body: some View {
        List {
            ForEach(availableFiles.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { fileType in
                if let entries = availableFiles[fileType] {
                    Section("\(fileType.displayName) (\(entries.count))") {
                        ForEach(entries) { entry in
                            FileDownloadRow(
                                fileType: fileType,
                                entry: entry,
                                isDownloading: downloadingFiles.contains("\(fileType.rawValue)-\(entry.id)"),
                                showSegmentNumber: true
                            ) {
                                await onDownload(fileType, entry)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("All Segments")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - File Download Row

struct FileDownloadRow: View {
    let fileType: FileType
    let entry: RouteFileEntry
    let isDownloading: Bool
    var showSegmentNumber: Bool = true
    let action: () async -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.subheadline.weight(.medium))

                Text(entry.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isDownloading {
                ProgressView()
            } else {
                Button {
                    HapticManager.buttonPress()
                    Task {
                        await action()
                    }
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(Color.themeGreen)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    private var titleText: String {
        if showSegmentNumber, let segment = entry.segmentNumber {
            return "\(fileType.displayName) - Segment \(segment)"
        }
        return fileType.displayName
    }
}

// MARK: - Downloaded File Document

struct DownloadedFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: tempURL)
        self.fileURL = tempURL
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: fileURL, options: .immediate)
    }
}
