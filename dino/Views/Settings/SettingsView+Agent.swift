//
//  SettingsView+Agent.swift
//  dino
//
//  Created for Dino Browser.
//  Developer settings for Copilot, AI model providers, API keys,
//  local driver endpoints, and autonomous safety rails.
//

import SwiftUI
import AppKit

extension SettingsView {

    var agentSection: some View {
        AgentSettingsContent()
    }
}

private struct AgentSettingsContent: View {
    @ObservedObject private var runtime = DinoAgentRuntime.shared
    @ObservedObject private var settings = SettingsStore.shared
    private let vault = DinoModelVault.shared

    @State private var activeProvider: DinoModelProvider = DinoModelVault.shared.activeProvider
    @State private var selectedModel: String = DinoModelVault.shared.selectedModel
    @State private var apiKeyInput: String = ""
    @State private var ollamaEndpointInput: String = DinoModelVault.shared.ollamaEndpoint
    @State private var saveStatusMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            headerView

            aiProviderCard
            driverEndpointsCard
            safetyRailsCard
        }
        .onAppear {
            activeProvider = vault.activeProvider
            selectedModel = vault.selectedModel
            apiKeyInput = vault.key(for: activeProvider) ?? ""
            ollamaEndpointInput = vault.ollamaEndpoint
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Copilot & Agents")
                .font(Theme.panelTitleFont)
                .foregroundStyle(Theme.ink)

            Text("Configure in-browser AI providers, local automation endpoints, and autonomous safety boundaries.")
                .font(Theme.font(size: 13))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: - AI Provider Card

    private var aiProviderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Model Provider")
                .font(Theme.font(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)

            // Provider Picker
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Provider")
                        .font(Theme.font(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text("Active LLM backend for in-browser automation.")
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.muted)
                }

                Spacer()

                Menu {
                    ForEach(DinoModelProvider.allCases) { provider in
                        Button(action: {
                            activeProvider = provider
                            vault.activeProvider = provider
                            selectedModel = vault.selectedModel
                            apiKeyInput = vault.key(for: provider) ?? ""
                        }) {
                            if activeProvider == provider {
                                Label(provider.displayName, systemImage: "checkmark")
                            } else {
                                Text(provider.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(activeProvider.displayName)
                            .font(Theme.font(size: 12, weight: .medium))
                            .foregroundStyle(Theme.ink)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.press, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.activeTabHairline, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
            }

            Rectangle()
                .fill(Theme.activeTabHairline)
                .frame(height: 0.5)

            // Model Selection
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model Name")
                        .font(Theme.font(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text("Model identifier invoked via REST endpoint.")
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.muted)
                }

                Spacer()

                Menu {
                    ForEach(activeProvider.availableModels, id: \.self) { m in
                        Button(action: {
                            selectedModel = m
                            vault.selectedModel = m
                        }) {
                            if selectedModel == m {
                                Label(m, systemImage: "checkmark")
                            } else {
                                Text(m)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedModel)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.ink)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.press, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)
            }

            Rectangle()
                .fill(Theme.activeTabHairline)
                .frame(height: 0.5)

            // API Key / Endpoint Configuration
            if activeProvider.requiresAPIKey {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("API Key")
                            .font(Theme.font(size: 12, weight: .medium))
                            .foregroundStyle(Theme.ink)

                        Spacer()

                        if vault.hasKey(for: activeProvider) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: 0x8FAE8B))
                                    .frame(width: 5, height: 5)
                                Text("Stored in local vault (0600)")
                                    .font(Theme.font(size: 10))
                                    .foregroundStyle(Theme.faint)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        SecureField("Paste \(activeProvider.displayName) API key...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                        Button("Save") {
                            let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                vault.saveKey(trimmed, for: activeProvider)
                                saveStatusMessage = "Key saved successfully"
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if vault.hasKey(for: activeProvider) {
                            Button("Clear", role: .destructive) {
                                vault.deleteKey(for: activeProvider)
                                apiKeyInput = ""
                                saveStatusMessage = "Key removed"
                            }
                            .controlSize(.small)
                        }
                    }

                    Text("Stored locally in ~/Library/Application Support/dino/agent_vault.json with POSIX 0600 permissions. Never transmitted off your device.")
                        .font(Theme.font(size: 10))
                        .foregroundStyle(Theme.faint)
                }
            } else {
                // Ollama Endpoint
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ollama Endpoint")
                        .font(Theme.font(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)

                    HStack(spacing: 8) {
                        TextField("http://localhost:11434/v1", text: $ollamaEndpointInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                        Button("Save") {
                            vault.ollamaEndpoint = ollamaEndpointInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            saveStatusMessage = "Endpoint saved"
                        }
                        .controlSize(.small)
                    }

                    Text("Local OpenAI-compatible inference endpoint without network egress.")
                        .font(Theme.font(size: 10))
                        .foregroundStyle(Theme.faint)
                }
            }

            if let msg = saveStatusMessage {
                Text(msg)
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Color(hex: 0x8FAE8B))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.hover)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.activeTabHairline, lineWidth: 1)
        )
    }

    // MARK: - Driver Endpoints Card

    private var driverEndpointsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Local Automation Drivers")
                .font(Theme.font(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)

            endpointRow(
                protocolName: "HTTP / CDP Server",
                address: "http://127.0.0.1:\(DinoAgentServer.defaultPort)",
                description: "DevTools protocol (/json/list) and REST agent endpoints for Python/TypeScript SDKs."
            )

            Rectangle()
                .fill(Theme.activeTabHairline)
                .frame(height: 0.5)

            endpointRow(
                protocolName: "UNIX Domain Socket",
                address: "~/.dino/dino.sock",
                description: "Low-latency IPC for CLI driver commands (snap, click, type, shot)."
            )

            Rectangle()
                .fill(Theme.activeTabHairline)
                .frame(height: 0.5)

            endpointRow(
                protocolName: "MCP Stdio Server",
                address: "dino mcp",
                description: "Direct Model Context Protocol bridge for Claude Desktop, Cursor, and Antigravity."
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.hover)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.activeTabHairline, lineWidth: 1)
        )
    }

    private func endpointRow(protocolName: String, address: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: 0x8FAE8B))
                        .frame(width: 5, height: 5)

                    Text(protocolName)
                        .font(Theme.font(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)

                    Text(address)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }

                Text(description)
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.faint)
            }
            Spacer()
        }
    }

    // MARK: - Safety Rails Card

    private var safetyRailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Autonomous Safety Boundaries")
                .font(Theme.font(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Human-in-the-Loop Confirmation")
                        .font(Theme.font(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)

                    Text("Requires manual human approval before clicking purchase, checkout, or account deletion buttons.")
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("Enforced")
                    .font(Theme.font(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.press, in: Capsule())
            }

            Rectangle()
                .fill(Theme.activeTabHairline)
                .frame(height: 0.5)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anti-Bot Challenge Auto-Pause")
                        .font(Theme.font(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)

                    Text("Automatically pauses autonomous execution when Cloudflare, Turnstile, or CAPTCHA challenges appear.")
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("Active")
                    .font(Theme.font(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: 0x8FAE8B))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.press, in: Capsule())
            }

            Rectangle()
                .fill(Theme.activeTabHairline)
                .frame(height: 0.5)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Max Steps per Mission")
                        .font(Theme.font(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)

                    Text("Hard limit on the cognitive loop to prevent infinite navigation cycles.")
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("25 Steps")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.hover)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.activeTabHairline, lineWidth: 1)
        )
    }
}
