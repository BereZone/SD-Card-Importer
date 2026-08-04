import SwiftUI

/// Finding cards, getting permission to read them, and scanning what is on them.
extension ImportViewModel {

    // MARK: - Volumes

    func refreshVolumes(autoPrompt: Bool = false, autoScan: Bool = false) {
        log("Refreshing volumes…")

        // Attempt to reconnect to the destination drive if it just mounted.
        if destinationURL == nil, let data = destBookmarkData {
            if let restored = permissionService.restoreDestinationBookmark(from: data) {
                destinationURL = restored
                log("Restored destination drive connection.")
            }
        }

        // A mount or unmount during an import must not empty the list the import
        // is working through: the volume list still refreshes, but the candidate
        // set and the user's selection survive until the import finishes.
        if isImporting {
            log("Volume list changed during an import — keeping the current file list.", .caution)
        } else {
            clearCandidates()
        }

        var results: [URL] = permissionService.restoreSourceBookmarks()

        let destRoot = destinationVolumeRoot()
        let discovered = scanner.getMountedVolumes(ignoring: sessionIgnoredPaths, destRoot: destRoot)

        var existingPaths = Set(results.map { $0.standardizedFileURL.path })
        for d in discovered where !existingPaths.contains(d.standardizedFileURL.path) {
            results.append(d)
            existingPaths.insert(d.standardizedFileURL.path)
        }

        results.removeAll { $0.standardizedFileURL.path == "/" }

        // Prefer the security-scoped URL for a path when there is one: it is the
        // handle that can actually read the card.
        var byPath: [String: URL] = [:]
        for u in results {
            let path = u.standardizedFileURL.path
            if let scoped = permissionService.scopedURLForVolumePath[path] {
                byPath[path] = scoped
            } else if byPath[path] == nil {
                byPath[path] = u
            }
        }

        removableVolumes = byPath.values.sorted { $0.lastPathComponent < $1.lastPathComponent }

        let labels = removableVolumes.map { u -> String in
            permissionService.scopedURLForVolumePath[u.standardizedFileURL.path] != nil
                ? "\(u.lastPathComponent) (scoped)"
                : "\(u.lastPathComponent)"
        }
        log("Detected camera cards: \(labels)")

        if autoPrompt {
            let unscoped = removableVolumes.filter {
                permissionService.scopedURLForVolumePath[$0.standardizedFileURL.path] == nil
            }
            if !unscoped.isEmpty {
                Task { await requestAccess(to: unscoped, autoScan: autoScan) }
                return
            }
        }

        if autoScan && !removableVolumes.isEmpty {
            scanForCandidates()
        }
    }

    private func destinationVolumeRoot() -> URL? {
        guard let dest = destinationURL?.standardizedFileURL else { return nil }
        let c = dest.pathComponents
        guard c.count > 2, c[0] == "/", c[1] == "Volumes" else { return nil }
        return URL(fileURLWithPath: "/Volumes/\(c[2])")
    }

    /// Cards hidden by the remove button, which a plain refresh will not bring
    /// back because it re-applies the ignore list.
    var hiddenCardCount: Int { sessionIgnoredPaths.count }

    /// Refresh, and un-hide anything previously removed from the list.
    ///
    /// This is what the Refresh control is wired to. Removing a card only adds it
    /// to `sessionIgnoredPaths`, so a refresh that respected that list made an
    /// accidental removal permanent for the session with no way back.
    func clearIgnoresAndRefresh() {
        if !sessionIgnoredPaths.isEmpty {
            log("Restoring \(sessionIgnoredPaths.count) removed card(s).")
        }
        sessionIgnoredPaths.removeAll()
        refreshVolumes(autoPrompt: true, autoScan: true)
    }

    func removeVolumeFromList(for url: URL) {
        permissionService.removeVolumeBookmark(for: url, ignoredPaths: &sessionIgnoredPaths)
        if let root = DestinationPlanner.volumeRootPath(for: url) {
            customBucketsPhotos.removeValue(forKey: root)
            customBucketsVideos.removeValue(forKey: root)
            saveCustomBuckets()
        }
        refreshVolumes(autoPrompt: false)
    }

    // MARK: - Permission

    func requestAccess(to volumes: [URL], autoScan: Bool = false) async {
        let granted = await permissionService.promptForAccess(to: volumes)
        if !granted.isEmpty {
            permissionService.appendSourceBookmarks(for: granted)
            for u in granted {
                sessionIgnoredPaths.remove(u.standardizedFileURL.path)
            }
            refreshVolumes(autoPrompt: false, autoScan: autoScan)
            log("Granted access for: \(granted.map(\.lastPathComponent))")
        } else {
            log("Access not granted; scanning will show 0 files.")
        }
    }

    func addSourceVolume() async {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Grant Access"

        if panel.runModal() == .OK {
            permissionService.appendSourceBookmarks(for: panel.urls)
            for u in panel.urls { sessionIgnoredPaths.remove(u.standardizedFileURL.path) }
            refreshVolumes(autoPrompt: false, autoScan: true)
            log("Granted access for: \(panel.urls.map(\.lastPathComponent))")
        }
    }

    // MARK: - Scanning

    /// Drops the candidate list and the thumbnails rendered for it. The thumbnail
    /// cache is keyed by file URL, so without this an ejected or rescanned card's
    /// bitmaps stay resident with nothing on screen referencing them.
    func clearCandidates() {
        candidates = []
        disabledCandidates = []
        Task { await ThumbnailService.shared.clear() }
    }

    func scanForCandidates() {
        log("Scanning volumes…")
        clearCandidates()
        progress = 0

        let vols = removableVolumes
        let totalVols = max(vols.count, 1)

        let volumeData: [(URL, URL)] = vols.map {
            let token = permissionService.scopedURLForVolumePath[$0.standardizedFileURL.path] ?? $0
            return ($0, token)
        }

        let isDebug = debugScan

        let logMsg: @Sendable (String) -> Void = { msg in
            Task { @MainActor [weak self] in self?.log(msg) }
        }
        let updateProgress: @Sendable (Double) -> Void = { p in
            Task { @MainActor [weak self] in self?.progress = p }
        }

        Task {
            // Detached: scanning walks the whole card and reads EXIF, which must
            // not happen on the main actor.
            let found = await Task.detached(priority: .userInitiated) { () -> [ImportCandidate] in
                var results: [ImportCandidate] = []
                let service = FileScanningService()

                for (i, (vol, tokenized)) in volumeData.enumerated() {
                    logMsg("• \(vol.path)")
                    updateProgress(Double(i) / Double(totalVols))
                    results.append(contentsOf: service.scanVolume(
                        vol, tokenizedURL: tokenized, debugScan: isDebug, log: logMsg
                    ))
                }
                return results
            }.value

            let filtered = found.filter { self.passesDateFilter($0) }

            self.candidates = filtered
            self.progress = 1.0
            self.log("Found \(filtered.count) files (filtered from \(found.count)).")
        }
    }

    /// Whether a discovered file survives the user's date filter.
    private func passesDateFilter(_ candidate: ImportCandidate) -> Bool {
        switch options.dateFilter {
        case .all:
            return true
        case .sinceLastImport:
            return candidate.date.timeIntervalSince1970 > lastImportDate
        case .today:
            return Calendar.current.isDateInToday(candidate.date)
        case .last7Days:
            guard let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else {
                return true
            }
            return candidate.date > sevenDaysAgo
        case .customRange:
            // Widened to whole days at both ends, so a range is inclusive of the
            // days the user picked rather than of two instants.
            let start = Calendar.current.startOfDay(for: options.customStartDate)
            let end = Calendar.current.date(
                bySettingHour: 23, minute: 59, second: 59, of: options.customEndDate
            ) ?? options.customEndDate
            return candidate.date >= start && candidate.date <= end
        }
    }

    // MARK: - Mount notifications

    func observeMounts() {
        let nc = NSWorkspace.shared.notificationCenter

        // The notification block is not actor-isolated even though it is delivered
        // on the main queue, so the work hops onto the main actor explicitly.
        let didMount = nc.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.log("Volume mounted")
                self.refreshVolumes(autoPrompt: true, autoScan: true)
            }
        }

        let didUnmount = nc.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.log("Volume unmounted")
                self.refreshVolumes()
            }
        }

        observers = [didMount, didUnmount]
    }
}
