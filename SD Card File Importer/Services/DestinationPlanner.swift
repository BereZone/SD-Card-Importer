import Foundation

/// Resolves where a file will land, from the four inputs that decide it: the
/// folder template, the per-card folder assignment, the auto-detected camera
/// profile, and the file's capture date.
///
/// A value type with no published state and no view behind it. Every mistake this
/// app can make is a destination mistake, so this is the part that most needs to
/// be readable on its own and checkable without a running window. It is built
/// fresh from view model state at each call site rather than held, so it can never
/// answer from a stale copy of the user's settings.
struct DestinationPlanner {
    let options: ImportOptions
    let customBucketsPhotos: [String: String]
    let customBucketsVideos: [String: String]
    let volumeBucketOverride: [String: String]
    var profileManager: CameraProfileManager = .shared

    // MARK: - Volume paths

    /// The `/Volumes/<name>` root a file sits under. This is the key every
    /// per-card setting is stored against, so it has to be derived the same way
    /// everywhere. Files outside `/Volumes` fall back to their containing folder.
    nonisolated static func volumeRootPath(for url: URL) -> String? {
        let components = url.standardizedFileURL.pathComponents
        guard components.count >= 3, components[0] == "/", components[1] == "Volumes" else {
            return url.standardizedFileURL.deletingLastPathComponent().path
        }
        return "/\(components[1])/\(components[2])"
    }

    // MARK: - Folder names

    /// Folder names come from a free text field, and the result is appended to a
    /// file URL. Unsanitised, "2026/Wedding" silently created a nested folder and
    /// ".." walked up out of the destination entirely.
    nonisolated static func sanitizeFolderName(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "/", with: "-")
        cleaned = cleaned.replacingOccurrences(of: ":", with: "-")
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Destinations

    /// The folder name for a file's camera, which is either what the user pinned
    /// to that card or what the profiles detected from the card's layout.
    ///
    /// A pinned name is used literally: the user typed it, so appending a
    /// "Photos"/"Videos" category to it would be overriding the thing they asked
    /// for.
    func cameraBucket(for c: ImportCandidate) -> String {
        let isVideo = MediaTypes.isVideoCategory(c.url)
        var customBase: String? = nil

        if let root = Self.volumeRootPath(for: c.url) {
            customBase = isVideo ? customBucketsVideos[root] : customBucketsPhotos[root]
        }

        if customBase == nil,
           let volName = c.url.pathComponents.dropFirst(2).first,
           let mapped = volumeBucketOverride[volName] {
            customBase = mapped
        }

        if let base = customBase {
            return base
        }
        return profileManager.bucket(for: c.url)
    }

    /// The full destination URL for one file, including its file name.
    func destination(for c: ImportCandidate, root: URL) -> URL {
        let englishMonthFormatter = DateFormatter()
        englishMonthFormatter.locale = Locale(identifier: "en_US_POSIX")
        englishMonthFormatter.dateFormat = "MMMM"

        let cal = Calendar(identifier: .gregorian)
        let y = cal.component(.year, from: c.date)
        let m = cal.component(.month, from: c.date)
        let d = cal.component(.day, from: c.date)

        let monthName = englishMonthFormatter.monthSymbols[m - 1]
        let monthFolder = String(format: "%02d_%@", m, monthName)
        let dayFolder = String(format: "%02d", d)

        let bucket = cameraBucket(for: c)

        var segments = options.folderTemplate.components(separatedBy: "/")
        segments = segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var desired: [String] = []
        for seg in segments {
            var s = seg
            s = s.replacingOccurrences(of: "{YYYY}", with: "\(y)")
            s = s.replacingOccurrences(of: "{MM}", with: monthFolder)
            s = s.replacingOccurrences(of: "{DD}", with: dayFolder)
            s = s.replacingOccurrences(of: "{Camera}", with: bucket)
            desired.append(s)
        }

        var url = root.standardizedFileURL
        // Skip template segments the user's chosen destination already ends with
        // (e.g. dest ".../Footage/A7C" with template "{Camera}/..." shouldn't nest
        // another "A7C"). Only the trailing components are considered — matching
        // anywhere in the path would let an unrelated ancestor folder swallow a
        // template level.
        let existing = Set(url.pathComponents.suffix(desired.count).map { $0.lowercased() })

        for seg in desired where !existing.contains(seg.lowercased()) {
            url.append(path: seg)
        }

        let fileName = options.renameFiles
            ? filename(for: c, template: options.renameTemplate)
            : c.url.lastPathComponent
        return url.appending(path: fileName)
    }

    /// The destination as a path relative to the chosen root, which is what the
    /// interface shows. Falls back to the absolute path if the destination somehow
    /// sits outside the root.
    func relativeDestination(for c: ImportCandidate, root: URL) -> String {
        let full = destination(for: c, root: root)
        let rootComponents = root.standardizedFileURL.pathComponents
        let fullComponents = full.standardizedFileURL.pathComponents
        guard fullComponents.count > rootComponents.count,
              Array(fullComponents.prefix(rootComponents.count)) == rootComponents else {
            return full.path
        }
        return fullComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    /// Applies the rename template to one file.
    func filename(for c: ImportCandidate, template: String) -> String {
        let cal = Calendar(identifier: .gregorian)
        let y = String(format: "%04d", cal.component(.year, from: c.date))
        let m = String(format: "%02d", cal.component(.month, from: c.date))
        let d = String(format: "%02d", cal.component(.day, from: c.date))

        let camera = cameraBucket(for: c)
        let originalName = c.url.deletingPathExtension().lastPathComponent
        let originalExt = c.url.pathExtension

        var result = template
        result = result.replacingOccurrences(of: "{YYYY}", with: y)
        result = result.replacingOccurrences(of: "{MM}", with: m)
        result = result.replacingOccurrences(of: "{DD}", with: d)
        result = result.replacingOccurrences(of: "{Camera}", with: camera)
        result = result.replacingOccurrences(of: "{OriginalName}", with: originalName)
        result = result.replacingOccurrences(of: "{OriginalExtension}", with: originalExt)

        // Only append the extension if the template didn't already place it.
        if !template.contains("{OriginalExtension}") && !originalExt.isEmpty {
            result += ".\(originalExt)"
        }

        return result
    }

    // MARK: - Collisions

    /// Finds a destination name that isn't taken, by appending _1, _2, … before
    /// the extension.
    nonisolated static func resolveCollision(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var i = 1
        while true {
            let name = ext.isEmpty ? "\(base)_\(i)" : "\(base)_\(i).\(ext)"
            let candidate = dir.appending(path: name)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            i += 1
        }
    }

    // MARK: - Where files actually landed

    /// Narrows a running common-ancestor path to also cover `url`'s directory.
    /// `nil` means "nothing folded in yet", so the first file seeds the ancestor.
    ///
    /// Folded as the import runs rather than collected: the full list of imported
    /// URLs was only ever reduced to this, so holding one path per file until the
    /// end was pure accumulation.
    nonisolated static func mergeCommonFolder(_ current: [String]?, with url: URL) -> [String] {
        let dir = url.deletingLastPathComponent().pathComponents
        guard let current else { return dir }

        var merged: [String] = []
        for i in 0..<min(current.count, dir.count) {
            if current[i] == dir[i] {
                merged.append(current[i])
            } else {
                break
            }
        }
        return merged
    }

    nonisolated static func folderURL(from components: [String]?) -> URL? {
        guard let components, !components.isEmpty else { return nil }
        var result = URL(fileURLWithPath: "/")
        for comp in components where comp != "/" {
            result.append(path: comp)
        }
        return result
    }
}
