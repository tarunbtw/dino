//
//  SettingsView+Agent.swift
//  dino
//
//  Created for Dino Browser.
//  Developer settings for Agent, AI model providers, API keys, and endpoints.
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
    private let vault = DinoModelVault.shared

    @State private var activeProvider: DinoModelProvider = DinoModelVault.shared.activeProvider
    @State private var selectedModel: String = DinoModelVault.shared.selectedModel
    @State private var apiKeyInput: String = ""
    @State private var ollamaEndpointInput: String = DinoModelVault.shared.ollamaEndpoint
    @State private var saveStatusMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerView

            providerCard
        }
        .onAppear {
            syncFromVault()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Agent")
                .font(Theme.panelTitleFont)
                .foregroundStyle(Theme.ink)

            Text("Configure AI model provider and credentials.")
                .font(Theme.font(size: 13))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Model Configuration Card

    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Provider Picker Row
            HStack {
                Text("Provider")
                    .font(Theme.font(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)

                Spacer()

                Menu {
                    ForEach(DinoModelProvider.allCases) { provider in
                        Button(action: {
                            activeProvider = provider
                            vault.activeProvider = provider
                            selectedModel = vault.selectedModel
                            apiKeyInput = vault.key(for: provider) ?? ""
                            saveStatusMessage = nil
                        }) {
                            if activeProvider == provider {
                                Label(provider.displayName, systemImage: "checkmark")
                            } else {
                                Text(provider.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(activeProvider.displayName)
                            .font(Theme.font(size: 12, weight: .medium))
                            .foregroundStyle(Theme.ink)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
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

            // Preset Model Picker Row
            HStack {
                Text("Model")
                    .font(Theme.font(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)

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
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.ink)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.press, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)
            }

            // Custom Model Identifier Input
            HStack(spacing: 12) {
                Text("Custom Model")
                    .font(Theme.font(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)

                TextField("e.g. \(activeProvider.defaultModel)", text: $selectedModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                    .onSubmit {
                        let clean = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty {
                            vault.selectedModel = clean
                        }
                    }
            }

            Rectangle()
                .fill(Theme.activeTabHairline)
                .frame(height: 0.5)

            // API Key or Endpoint Row
            if activeProvider.requiresAPIKey {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("API Key")
                            .font(Theme.font(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)

                        Spacer()

                        if vault.hasKey(for: activeProvider) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: 0x8FAE8B))
                                    .frame(width: 5, height: 5)
                                Text("Key saved")
                                    .font(Theme.font(size: 11))
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
                                saveStatusMessage = "Key saved"
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
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Endpoint")
                        .font(Theme.font(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)

                    HStack(spacing: 8) {
                        TextField("http://localhost:11434/v1", text: $ollamaEndpointInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                        Button("Save") {
                            let trimmed = ollamaEndpointInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                vault.ollamaEndpoint = trimmed
                                saveStatusMessage = "Endpoint saved"
                            }
                        }
                        .controlSize(.small)
                    }
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

    private func syncFromVault() {
        activeProvider = vault.activeProvider
        selectedModel = vault.selectedModel
        apiKeyInput = vault.key(for: activeProvider) ?? ""
        ollamaEndpointInput = vault.ollamaEndpoint
    }
}
