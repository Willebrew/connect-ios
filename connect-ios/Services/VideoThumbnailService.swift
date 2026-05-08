//
//  VideoThumbnailService.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Generates and caches video thumbnails for scrubbing
//

import Foundation
import AVFoundation
import UIKit
import os

@Observable
final class VideoThumbnailService {
    private var thumbnailCache: [TimeInterval: UIImage] = [:]
    private var asset: AVAsset?
    private var generator: AVAssetImageGenerator?

    var isGenerating = false

    /// Load video asset for thumbnail generation
    func loadAsset(from url: URL) async {
        asset = AVAsset(url: url)

        // Configure image generator
        if let asset = asset {
            generator = AVAssetImageGenerator(asset: asset)
            generator?.appliesPreferredTrackTransform = true
            generator?.maximumSize = CGSize(width: 200, height: 112) // 16:9 aspect ratio thumbnails
            generator?.requestedTimeToleranceBefore = .zero
            generator?.requestedTimeToleranceAfter = .zero
        }
    }

    /// Get thumbnail for a specific time offset
    func getThumbnail(at offset: TimeInterval) async -> UIImage? {
        // Check cache first
        if let cached = thumbnailCache[offset] {
            return cached
        }

        // Generate new thumbnail
        guard let generator = generator else { return nil }

        isGenerating = true
        defer { isGenerating = false }

        let time = CMTime(seconds: offset / 1000, preferredTimescale: 600) // Convert ms to seconds

        do {
            let (cgImage, _) = try await generator.image(at: time)
            let image = UIImage(cgImage: cgImage)

            // Cache the thumbnail
            thumbnailCache[offset] = image

            return image
        } catch {
            Logger.data.error("Failed to generate thumbnail", error: error)
            return nil
        }
    }

    /// Pre-generate thumbnails for the entire timeline
    func preloadThumbnails(duration: TimeInterval, interval: TimeInterval = 10000) async {
        guard let generator = generator else { return }

        isGenerating = true
        defer { isGenerating = false }

        var times: [CMTime] = []
        var currentOffset: TimeInterval = 0

        while currentOffset <= duration {
            let time = CMTime(seconds: currentOffset / 1000, preferredTimescale: 600)
            times.append(time)
            currentOffset += interval
        }

        // Generate thumbnails in batch
        for time in times {
            let offset = TimeInterval(time.seconds) * 1000

            do {
                let (cgImage, _) = try await generator.image(at: time)
                let image = UIImage(cgImage: cgImage)
                thumbnailCache[offset] = image
            } catch {
                Logger.data.error("Failed to generate thumbnail", error: error)
            }
        }
    }

    /// Clear thumbnail cache
    func clearCache() {
        thumbnailCache.removeAll()
        generator = nil
        asset = nil
    }

    /// Get cache size
    var cacheCount: Int {
        thumbnailCache.count
    }
}
