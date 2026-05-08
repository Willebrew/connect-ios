//
//  DeviceRowSkeleton.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Skeleton loading view for device rows
//

import SwiftUI

struct DeviceRowSkeleton: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBox(width: 140, height: 18)
                    SkeletonBox(width: 100, height: 14)
                }

                Spacer()

                HStack(spacing: 12) {
                    SkeletonBox(width: 28, height: 28)
                    SkeletonBox(width: 28, height: 28)
                }
            }

            // Status indicator skeleton
            SkeletonBox(width: 80, height: 28)

            // Stats skeleton
            HStack(spacing: 24) {
                DeviceStatSkeleton()
                DeviceStatSkeleton()
                DeviceStatSkeleton()
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
}

struct DeviceStatSkeleton: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 4) {
            SkeletonBox(width: 50, height: 16)
            SkeletonBox(width: 60, height: 12)
        }
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        DeviceRowSkeleton()
        DeviceRowSkeleton()
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
