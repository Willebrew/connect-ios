//
//  DriveCardSkeleton.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Skeleton loading view for drive cards
//

import SwiftUI

struct DriveCardSkeleton: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header skeleton
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    SkeletonBox(width: 120, height: 18)
                    SkeletonBox(width: 150, height: 14)
                }
                Spacer()
            }

            // Stats skeleton
            HStack(spacing: 16) {
                SkeletonBox(width: 80, height: 14)
                SkeletonBox(width: 90, height: 14)
            }

            // Locations skeleton
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    SkeletonBox(width: 40, height: 16)
                    SkeletonBox(width: 180, height: 12)
                }

                HStack(spacing: 6) {
                    SkeletonBox(width: 32, height: 16)
                    SkeletonBox(width: 160, height: 12)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
}

struct SkeletonBox: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.gray.opacity(0.3))
            .frame(width: width, height: height)
    }
}

#Preview {
    VStack(spacing: 16) {
        DriveCardSkeleton()
        DriveCardSkeleton()
        DriveCardSkeleton()
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
