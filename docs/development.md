# Development

## Requirements

- macOS 14.0 or later
- Xcode 15 or later

If `xcodebuild` reports that it "requires Xcode, but active developer directory
is a command line tools instance", point it at your Xcode install:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Or set `DEVELOPER_DIR` for a single command, without changing the global setting:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build
```

## Building

```sh
make build     # release build
make debug     # debug build
make run       # build and launch
make clean     # remove build artifacts
```

Or open `SD Card File Importer.xcodeproj` in Xcode and press Run.

## Testing

```sh
make test
```

There is currently no test target in the Xcode project — `SD Card File
ImporterTests/` is an empty directory that was never wired up. `make test` and
the CI workflow both detect this and skip rather than fail. Adding a test target
in Xcode is enough to switch both on.

## Project layout

```
SD Card File Importer/
├── Models/          Value types: ImportCandidate, ImportOptions, MediaTypes
├── Services/        Filesystem and system work
│   ├── FileScanningService    Volume detection, media discovery, EXIF dates
│   ├── FileImportService      Streaming copy, SHA-256 verification, eject
│   ├── ThumbnailService       QuickLook thumbnail generation and caching
│   └── PermissionService      Security-scoped bookmarks for sandbox access
├── Strategies/      Per-manufacturer card layout detection
│   └── Profiles/    Canon, Nikon, Sony, Fujifilm, Panasonic, DJI, Generic
├── ViewModels/      ImportViewModel — all app state, @MainActor
├── Views/           SwiftUI views and components
└── DesignSystem/    Colors and shared styles
```

## Things worth knowing

**The app is sandboxed.** Access to cards and destinations comes from
security-scoped bookmarks managed by `PermissionService`. If a volume seems
unreadable in a debug build, the bookmark is the first thing to check.

**Imports run strictly sequentially.** `ImportViewModel.importAll()` awaits each
file before starting the next. This is deliberate — it keeps progress reporting
honest and avoids thrashing a card with concurrent reads.

**Copies stream in 1 MB chunks inside an autorelease pool.** The loop in
`FileImportService.copyFile` has no suspension point, so without a pool per chunk
every buffer for a file stays resident until that file finishes, and peak memory
tracks file size one-for-one. If you restructure that loop, measure
`phys_footprint` against a multi-gigabyte file before and after.

**Both file descriptors set `F_NOCACHE`.** A card import reads each byte once and
never re-reads it, so caching buys nothing and a large import would otherwise
displace the system's page cache. Verification depends on this too — a cached
read would verify nothing about what actually landed on disk.

**`MARKETING_VERSION` is the single source of truth for the version.** Do not
edit it by hand; see [releasing.md](releasing.md).
