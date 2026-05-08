//
//  TimelineSkeleton.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Skeleton loading view for timeline track only
//

import SwiftUI

struct TimelineSkeleton: View {
    @State private var isAnimating = false

    var body: some View {
        // Timeline track skeleton (just the scrubber portion)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Base track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 40)

                // Animated shimmer effect
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.3),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * 0.3, height: 40)
                    .offset(x: isAnimating ? geometry.size.width : -geometry.size.width * 0.3)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
        }
        .frame(height: 60)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    VStack {
        Spacer()
        VStack(spacing: 0) {
            TimelineSkeleton()
                .frame(height: 120)
                .background(.ultraThinMaterial)
        }
    }
    .background(Color.black)
}
