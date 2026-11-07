//
//  HitlBannerView.swift
//  nomad
//
//  Created by tarun on 15/10/26.
//

import SwiftUI
import Combine

/// Elegant in-browser Human-in-the-Loop notification banner.
/// Alerts the user when Cloudflare Turnstile, reCAPTCHA, or 2FA is present,
/// and automatically monitors the DOM to resume tasks the moment the challenge clears.
struct HitlBannerView: View {
    @ObservedObject var tab: Tab
    @State private var isChecking: Bool = false
    private let autoCheckTimer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Security Check Required")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let type = tab.hitlChallengeType {
                        Text("• \(type)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }

                Text("Complete the check directly in the page. Nomad will automatically resume.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    Task {
                        isChecking = true
                        let status = await tab.checkHitlStatus()
                        if status.resolved {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                                tab.isHitlActive = false
                                tab.hitlChallengeType = nil
                            }
                        }
                        isChecking = false
                    }
                }) {
                    HStack(spacing: 4) {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text("Check & Resume")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.orange.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        tab.isHitlActive = false
                        tab.hitlChallengeType = nil
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss Banner")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.96)
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.orange.opacity(0.3)),
            alignment: .bottom
        )
        .onReceive(autoCheckTimer) { _ in
            guard tab.isHitlActive else { return }
            Task {
                let status = await tab.checkHitlStatus()
                if status.resolved {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        tab.isHitlActive = false
                        tab.hitlChallengeType = nil
                    }
                }
            }
        }
    }
}

