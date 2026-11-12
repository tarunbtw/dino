//
//  DownloadManager.swift
//  dino
//
//  Created by tarun on 10/12/26.
//

import AppKit
import SwiftUI
import WebKit
import Combine
import CryptoKit

/// Represents an active or completed file download.
@MainActor
final class DownloadItem: NSObject, Identifiable, ObservableObject {
    let id: UUID = UUID()
    let originalURL: URL
    let date: Date = Date()
    
    @Published var suggestedFilename: String
    @Published var destinationURL: URL?
    @Published var progress: Double = 0.0
    @Published var totalBytes: Int64 = 0
    @Published var receivedBytes: Int64 = 0
    @Published var state: DownloadState = .downloading
    @Published var errorMessage: String? = nil
    @Published var completedAt: Date? = nil
    @Published var mimeType: String? = nil
    @Published var sha256: String? = nil

    enum DownloadState: String, Equatable {
        case downloading = "Downloading"
        case completed = "Completed"
        case failed = "Failed"
        case cancelled = "Cancelled"
    }

    weak var manager: DownloadManager?

    var formattedSize: String {
        if totalBytes > 0 {
            return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        } else if receivedBytes > 0 {
            return ByteCountFormatter.string(fromByteCount: receivedBytes, countStyle: .file)
        } else if state == .completed || destinationURL != nil {
            return "0 B"
        }
        return ""
    }

    var iconName: String {
        let ext = (suggestedFilename as NSString).pathExtension.lowercased()
        switch ext {
        case "dmg", "pkg": return "shippingbox.fill"
        case "zip", "tar", "gz", "rar": return "doc.zipper"
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "webp", "gif": return "photo"
        case "mp4", "mov", "webm": return "film"
        case "mp3", "wav", "m4a": return "music.note"
        default: return "doc.fill"
        }
    }

    var statusColor: Color {
        switch state {
        case .downloading: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }

    init(originalURL: URL, suggestedFilename: String, manager: DownloadManager) {
        self.originalURL = originalURL
        self.suggestedFilename = suggestedFilename.isEmpty ? "download" : suggestedFilename
        self.manager = manager
        super.init()
    }

    func cancel() {
        manager?.cancel(item: self)
    }
}

/// Central manager for WebKit downloads and macOS security quarantine tagging.
@MainActor
final class DownloadManager: NSObject, ObservableObject, WKDownloadDelegate {
    static let shared = DownloadManager()

    @Published private(set) var downloads: [DownloadItem] = []
    
    /// Strongly retains active WKDownload instances so ARC does not deallocate them during transfer.
    private var retainedDownloads: [ObjectIdentifier: WKDownload] = [:]
    private var progressObservers: [ObjectIdentifier: [NSKeyValueObservation]] = [:]

    /// Tracks if WebKit's network process encountered a TCC restriction writing to ~/Downloads in this session.
    private var hasTCCRestrictionOnDownloads: Bool = false

    var standardDownloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath()
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    var fallbackDirectory: URL {
        let fallback = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".dino/downloads")
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    /// Waiters awaiting download completion for agent automation.
    private var waiters: [UUID: (DownloadItem) -> Bool] = [:]

    var activeDownloads: [DownloadItem] {
        downloads.filter { $0.state == .downloading }
    }
    
    var hasActiveDownloads: Bool {
        !activeDownloads.isEmpty
    }

    var overallProgress: Double {
        let active = activeDownloads
        guard !active.isEmpty else { return 0 }
        let total = active.reduce(0.0) { $0 + $1.progress }
        return total / Double(active.count)
    }

    var downloadsDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["DINO_DOWNLOADS_PATH"], !custom.isEmpty {
            let u = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            return u
        }

        // Headless daemon: WebKit's out-of-process networking daemon (com.apple.WebKit.Networking.xpc)
        // is restricted from writing to ~/Downloads by macOS TCC in non-GUI / daemon sessions.
        // Directing WebKit to ~/.dino/downloads ensures 100% write reliability with zero prompts.
        // Completed files are then automatically promoted (copied) to ~/Downloads in downloadDidFinish.
        if DinoHeadlessManager.isHeadless || hasTCCRestrictionOnDownloads {
            return fallbackDirectory
        }

        return standardDownloadsDirectory
    }

    var displayPath: String {
        downloadsDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// Explicitly maps each WKDownload to its DownloadItem so state and progress never cross-talk.
    private var downloadItems: [ObjectIdentifier: DownloadItem] = [:]

    private override init() {
        super.init()
    }

    /// Registers a WKDownload, strongly retaining it and monitoring progress.
    func register(_ download: WKDownload, from url: URL, suggestedFilename: String = "download") {
        download.delegate = self
        let key = ObjectIdentifier(download)
        retainedDownloads[key] = download

        var initialName = suggestedFilename
        if initialName.isEmpty || initialName.lowercased() == "unknown" {
            let last = url.lastPathComponent
            initialName = (!last.isEmpty && last != "/" && last.lowercased() != "unknown") ? last : "download"
        }
        let cleanName = sanitizeFilename(initialName)
        let item = DownloadItem(originalURL: url, suggestedFilename: cleanName, manager: self)
        downloadItems[key] = item
        downloads.insert(item, at: 0)

        // Observe live progress from WebKit's NSProgress
        let p = download.progress
        var observations: [NSKeyValueObservation] = []

        observations.append(p.observe(\.fractionCompleted, options: [.initial, .new]) { [weak item] prog, _ in
            Task { @MainActor [weak item] in
                guard let item, item.state == .downloading else { return }
                item.progress = prog.fractionCompleted
                item.receivedBytes = prog.completedUnitCount
                item.totalBytes = prog.totalUnitCount
            }
        })

        progressObservers[key] = observations
    }

    // MARK: - WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let key = ObjectIdentifier(download)
        var chosenName = suggestedFilename
        if chosenName.isEmpty || chosenName.lowercased() == "unknown" {
            if let prior = downloadItems[key]?.suggestedFilename, !prior.isEmpty, prior.lowercased() != "unknown" {
                chosenName = prior
            } else if let urlName = response.url?.lastPathComponent, !urlName.isEmpty, urlName != "/", urlName.lowercased() != "unknown" {
                chosenName = urlName
            } else {
                chosenName = "download"
            }
        }
        let safeFilename = sanitizeFilename(chosenName)
        
        // Ensure ~/Downloads directory exists
        try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        
        let destination = uniqueDestinationURL(for: safeFilename)
        
        if let item = downloadItems[key] {
            item.suggestedFilename = safeFilename
            item.destinationURL = destination
            item.mimeType = response.mimeType
            if response.expectedContentLength > 0 {
                item.totalBytes = response.expectedContentLength
            }
        }
        
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        let item = downloadItems[key]
        defer {
            retainedDownloads.removeValue(forKey: key)
            downloadItems.removeValue(forKey: key)
            progressObservers.removeValue(forKey: key)
        }

        if let item = item {
            item.progress = 1.0
            item.state = .completed
            item.completedAt = Date()
            if let dest = item.destinationURL {
                var finalDest = dest
                if dest.path.contains(".dino/downloads") {
                    let targetURL = self.uniqueDestinationURL(for: item.suggestedFilename, in: self.standardDownloadsDirectory)
                    if (try? FileManager.default.copyItem(at: dest, to: targetURL)) != nil {
                        item.destinationURL = targetURL
                        finalDest = targetURL
                    }
                }
                if let attrs = try? FileManager.default.attributesOfItem(atPath: finalDest.path),
                   let fileSize = attrs[.size] as? Int64 {
                    item.receivedBytes = fileSize
                    if item.totalBytes <= 0 { item.totalBytes = fileSize }
                }
                item.sha256 = Self.computeSHA256(for: finalDest)
            }
            notifyWaiters(item)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let key = ObjectIdentifier(download)
        let item = downloadItems[key]

        let isPermissionError = (error as NSError).code == 513 ||
                                (error as NSError).code == 13 ||
                                error.localizedDescription.lowercased().contains("cannot create file") ||
                                error.localizedDescription.lowercased().contains("permission")

        if isPermissionError && !hasTCCRestrictionOnDownloads,
           let originatingWebView = download.webView {
            self.hasTCCRestrictionOnDownloads = true
            retainedDownloads.removeValue(forKey: key)
            downloadItems.removeValue(forKey: key)
            progressObservers.removeValue(forKey: key)

            if let resumeData = resumeData {
                originatingWebView.resumeDownload(fromResumeData: resumeData) { [weak self] resumedDownload in
                    guard let self = self, let item = item else { return }
                    self.register(resumedDownload, from: item.originalURL, suggestedFilename: item.suggestedFilename)
                    let newKey = ObjectIdentifier(resumedDownload)
                    self.downloadItems[newKey] = item
                }
                return
            } else if let origURL = item?.originalURL {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let newDownload = await originatingWebView.startDownload(using: URLRequest(url: origURL))
                    self.register(newDownload, from: origURL, suggestedFilename: item?.suggestedFilename ?? "download")
                }
                return
            }
        }

        defer {
            retainedDownloads.removeValue(forKey: key)
            downloadItems.removeValue(forKey: key)
            progressObservers.removeValue(forKey: key)
        }

        if let item = item {
            item.state = .failed
            item.errorMessage = error.localizedDescription
            item.completedAt = Date()
            notifyWaiters(item)
        }
    }

    private func notifyWaiters(_ item: DownloadItem) {
        var remaining: [UUID: (DownloadItem) -> Bool] = [:]
        for (id, waiter) in self.waiters {
            let handled = waiter(item)
            if !handled {
                remaining[id] = waiter
            }
        }
        self.waiters = remaining
    }

    // MARK: - Agent Download Interception & Handoff

    /// Formats a DownloadItem into a comprehensive JSON-compatible dictionary for agents.
    func itemDictionary(_ item: DownloadItem) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var effectiveBytes = item.receivedBytes
        var effectiveTotal = item.totalBytes
        if let dest = item.destinationURL, FileManager.default.fileExists(atPath: dest.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
           let onDisk = attrs[.size] as? Int64 {
            effectiveBytes = onDisk
            effectiveTotal = onDisk
        }
        let isDone = (item.state == .completed || item.destinationURL != nil)
        let sizeVal = isDone ? max(0, effectiveTotal >= 0 ? effectiveTotal : effectiveBytes) : (effectiveTotal > 0 ? effectiveTotal : effectiveBytes)
        let fmtSize: String
        if sizeVal == 0 && isDone {
            fmtSize = "0 B"
        } else if !item.formattedSize.isEmpty && item.formattedSize != "Zero KB" {
            fmtSize = item.formattedSize
        } else if isDone {
            fmtSize = sizeVal == 0 ? "0 B" : ByteCountFormatter.string(fromByteCount: sizeVal, countStyle: .file)
        } else {
            fmtSize = ""
        }

        var dict: [String: Any] = [
            "id": item.id.uuidString,
            "filename": item.suggestedFilename,
            "url": item.originalURL.absoluteString,
            "state": item.state.rawValue.lowercased(),
            "progress": item.progress,
            "totalBytes": effectiveTotal,
            "receivedBytes": effectiveBytes,
            "size": sizeVal,
            "formattedSize": fmtSize,
            "startedAt": iso.string(from: item.date)
        ]
        if let dest = item.destinationURL {
            dict["path"] = dest.path
            dict["destination"] = dest.path
            if item.state == .completed && FileManager.default.fileExists(atPath: dest.path) {
                if let sha = item.sha256 {
                    dict["sha256"] = sha
                } else if let computed = Self.computeSHA256(for: dest) {
                    item.sha256 = computed
                    dict["sha256"] = computed
                }
            }
        }
        if let mime = item.mimeType {
            dict["mimeType"] = mime
        }
        if let completedAt = item.completedAt {
            dict["completedAt"] = iso.string(from: completedAt)
        }
        if let err = item.errorMessage {
            dict["error"] = err
        }
        return dict
    }

    /// Returns the most recent download, or nil if none.
    func lastDownloadInfo() -> [String: Any]? {
        guard let item = downloads.first else { return nil }
        return itemDictionary(item)
    }

    /// Returns a list of recent downloads.
    func listDownloads(limit: Int = 20) -> [[String: Any]] {
        return downloads.prefix(max(1, limit)).map { itemDictionary($0) }
    }

    /// Computes the SHA-256 hex string for a local file using streaming chunks to minimize memory footprint.
    nonisolated static func computeSHA256(for fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Asynchronously waits for an active or impending file download to complete.
    func waitForDownload(timeoutMs: Int = 15000, since: Date? = nil, filename: String? = nil) async -> [String: Any] {
        let referenceDate = since ?? Date().addingTimeInterval(-300.0) // 5 minutes window

        let formatResponse: (DownloadItem, Bool, String?) -> [String: Any] = { item, success, error in
            let dict = self.itemDictionary(item)
            var resp = dict
            resp["download"] = dict
            resp["success"] = success
            if let error = error {
                resp["error"] = error
                resp["reason"] = "failed"
            }
            return resp
        }

        // 1. Check if a matching download already completed within the window
        let completedMatch = downloads.first { item in
            guard item.state == .completed else { return false }
            if let targetName = filename, !targetName.isEmpty,
               item.suggestedFilename != targetName && item.destinationURL?.lastPathComponent != targetName {
                return false
            }
            let itemDate = item.completedAt ?? item.date
            return itemDate >= referenceDate
        }

        if let completedItem = completedMatch {
            return formatResponse(completedItem, true, nil)
        }

        // 2. Wait up to timeoutMs for completion
        let waiterId = UUID()
        return await withCheckedContinuation { continuation in
            var resumed = false
            let safeResume: (([String: Any]) -> Void) = { dict in
                if !resumed {
                    resumed = true
                    continuation.resume(returning: dict)
                }
            }

            self.waiters[waiterId] = { item in
                if let targetName = filename, !targetName.isEmpty,
                   item.suggestedFilename != targetName && item.destinationURL?.lastPathComponent != targetName {
                    return false
                }
                if item.state == .completed {
                    safeResume(formatResponse(item, true, nil))
                } else {
                    safeResume(formatResponse(item, false, item.errorMessage ?? "Download failed"))
                }
                return true
            }

            Task {
                let sleepNanos = UInt64(max(50, timeoutMs)) * 1_000_000
                try? await Task.sleep(nanoseconds: sleepNanos)
                await MainActor.run {
                    if self.waiters.removeValue(forKey: waiterId) != nil {
                        if let lastCompleted = self.downloads.first(where: { item in
                            guard item.state == .completed else { return false }
                            if let targetName = filename, !targetName.isEmpty,
                               item.suggestedFilename != targetName && item.destinationURL?.lastPathComponent != targetName {
                                return false
                            }
                            return (item.completedAt ?? item.date) >= referenceDate
                        }) {
                            safeResume(formatResponse(lastCompleted, true, nil))
                        } else {
                            safeResume(["success": false, "reason": "timeout", "message": "Timed out waiting for download after \(timeoutMs)ms"])
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    func cancel(item: DownloadItem) {
        item.state = .cancelled
        if let key = downloadItems.first(where: { $0.value.id == item.id })?.key {
            retainedDownloads[key]?.cancel { _ in }
            retainedDownloads.removeValue(forKey: key)
            downloadItems.removeValue(forKey: key)
            progressObservers.removeValue(forKey: key)
        }
    }

    func showInFinder(_ item: DownloadItem) {
        guard let dest = item.destinationURL, FileManager.default.fileExists(atPath: dest.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dest])
    }

    /// Deletes a downloaded file from disk and removes it from the downloads list.
    @discardableResult
    func deleteDownload(filenameOrPath: String) -> Bool {
        let clean = filenameOrPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }

        let canonicalDownloads = downloadsDirectory.resolvingSymlinksInPath().standardized.path
        let expanded = (clean as NSString).expandingTildeInPath
        var targetURL: URL? = nil

        if FileManager.default.fileExists(atPath: expanded) {
            let candidate = URL(fileURLWithPath: expanded)
            let canonicalCandidate = candidate.resolvingSymlinksInPath().standardized.path
            let isInsideDownloads = canonicalCandidate.hasPrefix(canonicalDownloads + "/") || canonicalCandidate == canonicalDownloads
            let isRegistered = downloads.contains {
                $0.destinationURL?.resolvingSymlinksInPath().standardized.path == canonicalCandidate
            }
            if isInsideDownloads || isRegistered {
                targetURL = candidate
            }
        } else {
            let candidate = downloadsDirectory.appendingPathComponent(clean)
            let canonicalCandidate = candidate.resolvingSymlinksInPath().standardized.path
            if (canonicalCandidate.hasPrefix(canonicalDownloads + "/") || canonicalCandidate == canonicalDownloads) &&
               FileManager.default.fileExists(atPath: candidate.path) {
                targetURL = candidate
            }
        }

        var deletedFromDisk = false
        if let url = targetURL {
            try? FileManager.default.removeItem(at: url)
            deletedFromDisk = true
        }

        let initialCount = downloads.count
        downloads.removeAll(where: {
            $0.destinationURL?.path == expanded ||
            $0.destinationURL?.path == targetURL?.path ||
            $0.suggestedFilename == clean ||
            $0.id.uuidString.lowercased() == clean.lowercased()
        })
        let removedFromList = downloads.count < initialCount

        return deletedFromDisk || removedFromList
    }

    func openFile(_ item: DownloadItem) {
        guard let dest = item.destinationURL, FileManager.default.fileExists(atPath: dest.path) else { return }
        NSWorkspace.shared.open(dest)
    }

    func openDownloadsFolder() {
        NSWorkspace.shared.open(downloadsDirectory)
    }

    func removeDownload(_ item: DownloadItem) {
        cancel(item: item)
        downloads.removeAll { $0.id == item.id }
    }

    func clearCompleted() {
        downloads.removeAll { $0.state != .downloading }
    }


    // MARK: - Destination Disambiguation & Sanitization

    private func sanitizeFilename(_ filename: String) -> String {
        let raw = (filename.isEmpty || filename.lowercased() == "unknown") ? "download" : filename
        var clean = (raw as NSString).lastPathComponent
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty || clean == "." || clean == ".." || clean.hasPrefix(".") || clean.lowercased() == "unknown" {
            clean = "download" + (clean.isEmpty || clean.lowercased() == "unknown" ? "" : "_\(clean)")
        }
        return clean
    }

    private func uniqueDestinationURL(for filename: String, in directory: URL? = nil) -> URL {
        let targetDir = directory ?? downloadsDirectory
        let safeName = sanitizeFilename(filename)
        let base = targetDir.appendingPathComponent(safeName)
        if !FileManager.default.fileExists(atPath: base.path) {
            return base
        }

        let name = (safeName as NSString).deletingPathExtension
        let ext = (safeName as NSString).pathExtension
        var counter = 1
        
        while true {
            let candidateName = ext.isEmpty ? "\(name) (\(counter))" : "\(name) (\(counter)).\(ext)"
            let candidate = targetDir.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
