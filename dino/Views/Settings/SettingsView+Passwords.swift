//
//  SettingsView+Passwords.swift
//  dino
//
//  Created by tarun on 11/10/26.
//

import SwiftUI
import AppKit

extension SettingsView {

    var passwordsSection: some View {
        PasswordsSectionView()
    }
}

/// Dedicated Passwords management pane inside dino://settings.
private struct PasswordsSectionView: View {
    @State private var credentials: [StoredCredential] = []
    @State private var searchQuery: String = ""
    @State private var isAddingNew: Bool = false
    @State private var newHost: String = ""
    @State private var newUser: String = ""
    @State private var newPassword: String = ""
    @State private var copiedId: String? = nil
    @State private var errorMessage: String? = nil

    private var filteredCredentials: [StoredCredential] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return credentials }
        return credentials.filter {
            $0.host.lowercased().contains(q) || $0.user.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .center) {
                Text("Passwords")
                    .font(Theme.panelTitleFont)
                    .foregroundStyle(Theme.ink)

                Spacer()

                Button(action: {
                    isAddingNew.toggle()
                }) {
                    Label(isAddingNew ? "Cancel" : "Add Password", systemImage: isAddingNew ? "xmark" : "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(Theme.accent)
            }

            // Inline Add Form
            if isAddingNew {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add Login")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)

                    HStack(spacing: 10) {
                        TextField("Website (e.g. github.com)", text: $newHost)
                            .textFieldStyle(.roundedBorder)

                        TextField("Username or email", text: $newUser)
                            .textFieldStyle(.roundedBorder)

                        SecureField("Password", text: $newPassword)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Spacer()
                        Button("Save") {
                            saveNewCredential()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Theme.accent)
                    }
                }
                .padding(14)
                .background(Theme.hover, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
            }

            // Search Filter
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)

                TextField("Search passwords...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.hover, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border, lineWidth: 1))

            // Credentials List or Empty State
            if filteredCredentials.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.accent.opacity(0.7))

                    Text(credentials.isEmpty ? "No Saved Passwords" : "No Results")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)

                    Text(credentials.isEmpty
                         ? "Saved logins are stored in macOS Keychain."
                         : "No matches for \"\(searchQuery)\".")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredCredentials.enumerated()), id: \.element.id) { index, cred in
                        if index > 0 {
                            Divider()
                                .opacity(0.5)
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "globe")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.muted)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(cred.host)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                Text(cred.user)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                            }

                            Spacer()

                            // Copy Password Button (Prompts Touch ID)
                            Button(action: {
                                copyPassword(for: cred)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedId == cred.id ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 10))
                                    Text(copiedId == cred.id ? "Copied" : "Copy Password")
                                        .font(.system(size: 11))
                                }
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.press, in: RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)

                            // Delete Credential Button
                            Button(action: {
                                deleteCredential(cred)
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red.opacity(0.8))
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .help("Delete")
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                    }
                }
                .padding(10)
                .background(Theme.hover, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
            }
        }
        .onAppear {
            refreshList()
        }
    }

    private func refreshList() {
        credentials = KeychainVault.shared.allCredentials()
    }

    private func saveNewCredential() {
        let cleanH = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanU = newUser.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanH.isEmpty, !cleanU.isEmpty, !newPassword.isEmpty else {
            errorMessage = "Please fill in all fields."
            return
        }
        errorMessage = nil
        let success = KeychainVault.shared.save(host: cleanH, user: cleanU, secret: newPassword)
        if success {
            newHost = ""
            newUser = ""
            newPassword = ""
            isAddingNew = false
            refreshList()
        } else {
            errorMessage = "Failed to save into macOS Keychain."
        }
    }

    private func copyPassword(for cred: StoredCredential) {
        if let password = KeychainVault.shared.readPassword(for: cred) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(password, forType: .string)
            copiedId = cred.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if copiedId == cred.id {
                    copiedId = nil
                }
            }
        }
    }

    private func deleteCredential(_ cred: StoredCredential) {
        if KeychainVault.shared.delete(credential: cred) {
            refreshList()
        }
    }
}

