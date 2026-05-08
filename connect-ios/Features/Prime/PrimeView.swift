//
//  PrimeView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/14/25.
//
//  Prime subscription management
//

import SwiftUI
import os

struct PrimeView: View {
    let dongleId: String
    @State private var subscription: Subscription?
    @State private var subscribeInfo: SubscribeInfo?
    @State private var isLoading = true
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.yellow.gradient)

                        Text("comma prime")
                            .font(.largeTitle.bold())

                        Text("Put your car on the internet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(40)
                    } else if let subscription = subscription {
                        // Has subscription
                        subscriptionStatusCard(subscription)
                    } else {
                        // No subscription
                        subscribeCard
                    }

                    // Features list
                    featuresSection

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Prime")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadSubscription()
            }
        }
    }

    private func subscriptionStatusCard(_ sub: Subscription) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Subscription")
                        .font(.headline)

                    if sub.trial {
                        Text("Trial Period")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Plan", value: sub.plan)
                LabeledContent("Amount", value: "$\(sub.amount / 100)/month")
                LabeledContent("Since", value: sub.subscribedAt.dayMonthYear)

                if let cancelDate = sub.cancelAt {
                    LabeledContent("Cancels on", value: cancelDate.dayMonthYear)
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline)

            Button {
                manageSubscription()
            } label: {
                Text("Manage Subscription")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.themeGreen.gradient, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var subscribeCard: some View {
        VStack(spacing: 16) {
            if let info = subscribeInfo {
                Text("$\(info.amount / 100)")
                    .font(.system(size: 48, weight: .bold))
                +
                Text("/month")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button {
                subscribe()
            } label: {
                Text("Subscribe to Prime")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.themeGreen.gradient, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }

            Text("7-day free trial")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Features")
                .font(.title2.bold())

            VStack(spacing: 12) {
                FeatureRow(
                    icon: "pin.fill",
                    title: "100 Preserved Routes",
                    subtitle: "Keep your favorite drives forever"
                )

                FeatureRow(
                    icon: "icloud.and.arrow.up.fill",
                    title: "Unlimited Uploads",
                    subtitle: "Upload all your drive data"
                )

                FeatureRow(
                    icon: "map.fill",
                    title: "Device Locator",
                    subtitle: "Find your car on a map"
                )

                FeatureRow(
                    icon: "camera.fill",
                    title: "Remote Snapshots",
                    subtitle: "Take photos from your car"
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func loadSubscription() async {
        isLoading = true

        do {
            subscription = try await appState.apiClient.getSubscription(dongleId: dongleId)
            subscribeInfo = try await appState.apiClient.getSubscribeInfo(dongleId: dongleId)
        } catch {
            Logger.data.error("Failed to load subscription", error: error)
        }
        isLoading = false
    }

    private func subscribe() {
        // Open billing portal or use StoreKit
        if let url = URL(string: "https://billing.comma.ai/subscribe/\(dongleId)") {
            UIApplication.shared.open(url)
        }
    }

    private func manageSubscription() {
        // Open billing portal
        if let url = URL(string: "https://billing.comma.ai/manage/\(dongleId)") {
            UIApplication.shared.open(url)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.themeGreen)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    PrimeView(dongleId: "demo123")
        .environment(AppState.shared)
}
