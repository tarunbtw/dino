//
//  AgentPlaybookManager.swift
//  dino
//
//  Created by tarun on 15/10/26.
//

import Foundation
import Combine

/// Manages deterministic macro playbooks and action trajectories.
/// Enables recording repetitive browser flows and replaying them with zero token consumption.
@MainActor
final class AgentPlaybookManager: ObservableObject {
    static let shared = AgentPlaybookManager()

    @Published var isRecording: Bool = false
    @Published var activeRecordingName: String = ""
    @Published var recordedActions: [DinoAction] = []
    @Published var savedPlaybookNames: [String] = []

    private let playbooksDir: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.playbooksDir = home.appendingPathComponent(".dino/playbooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: playbooksDir, withIntermediateDirectories: true)
        refreshSavedList()
    }

    func refreshSavedList() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: playbooksDir, includingPropertiesForKeys: nil) else { return }
        self.savedPlaybookNames = files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    func startRecording(name: String = "playbook") {
        self.activeRecordingName = name.isEmpty ? "playbook_\(Int(Date().timeIntervalSince1970))" : name
        self.recordedActions = []
        self.isRecording = true
    }

    func record(action: DinoAction) {
        guard isRecording else { return }
        recordedActions.append(action)
    }

    @discardableResult
    func stopRecording() -> [DinoAction] {
        guard isRecording else { return [] }
        isRecording = false
        let name = activeRecordingName
        let actions = recordedActions
        save(name: name, actions: actions)
        return actions
    }

    func save(name: String, actions: [DinoAction]) {
        let fileURL = playbooksDir.appendingPathComponent("\(name).json")
        if let data = try? JSONEncoder().encode(actions) {
            try? data.write(to: fileURL)
            refreshSavedList()
        }
    }

    func load(name: String) -> [DinoAction]? {
        let fileURL = playbooksDir.appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: fileURL),
              let actions = try? JSONDecoder().decode([DinoAction].self, from: data) else {
            return nil
        }
        return actions
    }

    func delete(name: String) {
        let fileURL = playbooksDir.appendingPathComponent("\(name).json")
        try? FileManager.default.removeItem(at: fileURL)
        refreshSavedList()
    }

    /// Deterministically replays an action trajectory on the target tab with optional parameter interpolation.
    func replay(actions: [DinoAction], variables: [String: String] = [:], on tab: Tab) async throws -> (success: Bool, executed: Int, error: String?) {
        var count = 0
        for action in actions {
            let activeAction = action.interpolated(with: variables)
            let res = try await tab.performAction(activeAction)
            if !res.success {
                return (false, count, res.message)
            }
            count += 1
            // Natural settlement pause between deterministic replay steps
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return (true, count, nil)
    }
}

