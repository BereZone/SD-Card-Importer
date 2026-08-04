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
├── Models/          Value types, no behaviour of their own
│   ├── ImportCandidate        One discovered file
│   ├── ImportOptions          Everything the user can set
│   ├── ImportResult           What a finished import did
│   ├── LogEntry               One line of history
│   ├── MediaTypes             Which extensions count as photo or video
│   └── Formatting             Shared byte and duration formatting
├── Services/        Filesystem and system work
│   ├── FileScanningService    Volume detection, media discovery, EXIF dates
│   ├── FileImportService      Streaming copy, SHA-256 verification, eject
│   ├── DestinationPlanner     Where a file will land, and under what name
│   ├── TransferRateEstimator  Rolling-window transfer rate and time remaining
│   ├── ThumbnailService       QuickLook thumbnail generation and caching
│   └── PermissionService      Security-scoped bookmarks for sandbox access
├── Strategies/      Per-manufacturer card layout detection
│   └── Profiles/    Canon, Nikon, Sony, Fujifilm, Panasonic, DJI, Generic
├── ViewModels/      @MainActor
│   ├── ImportSession          Runs one import and reports the outcome
│   ├── ImportViewModel        Published state and the entry points views call
│   ├── ImportViewModel+Cards        Card discovery, permission, scanning
│   └── ImportViewModel+Persistence  Settings that outlive a launch
├── Views/           SwiftUI views and components
└── DesignSystem/    Colors and shared styles
```

`ImportViewModel` is a façade, not an engine. It holds the published state SwiftUI
binds to and delegates the actual work to types that do not know the interface
exists. Two of those are worth knowing about before changing anything:

- **`DestinationPlanner`** resolves the four inputs that decide where a file goes
  — folder template, per-card folder assignment, detected camera profile, capture
  date. Every mistake this app can make is a destination mistake, and they are all
  made here.
- **`ImportSession`** runs one import from a snapshot of the plan and reports back
  through closures. It never reads live view state, which is what stops a card
  being pulled mid-run from changing the work in flight.

## Things worth knowing

**The app is sandboxed.** Access to cards and destinations comes from
security-scoped bookmarks managed by `PermissionService`. If a volume seems
unreadable in a debug build, the bookmark is the first thing to check.

**Files are imported strictly one at a time.** `ImportSession.run()` awaits each
file before starting the next. This is deliberate — it keeps progress reporting
honest and avoids thrashing a card with concurrent reads. The overlap described
below happens *within* a single file, not across files.

**Copies stream in 8 MB chunks inside an autorelease pool.** The loop lives in
`FileImportService.streamCopy` and has no suspension point, so without a pool per
chunk every buffer for a file stays resident until that file finishes, and peak
memory tracks file size one-for-one. The chunk size is measured, not arbitrary —
`FileImportService.chunkSize` carries the numbers and the reasoning. Throughput
plateaus from 4 MB up; dropping back to 1 MB costs about 12%. If you restructure
that loop, measure `phys_footprint` against a multi-gigabyte file before and
after, and re-measure throughput against real removable media rather than a
RAM-backed disk image.

**Reads and writes overlap inside a file.** `streamCopy` hands each chunk to a
serial write queue with a depth-2 semaphore, so the card keeps streaming instead
of idling through every write. Measured on a UHS-II V60 card this took a 321 MB
clip from 192 to 246 MB/s writing to exFAT. Depth 2 bounds the in-flight buffers
to about three chunks, which is what keeps memory flat.

**Both file descriptors set `F_NOCACHE`.** A card import reads each byte once and
never re-reads it, so caching buys nothing and a large import would otherwise
displace the system's page cache. Verification depends on this too — a cached
read would verify nothing about what actually landed on disk.

**`MARKETING_VERSION` is the single source of truth for the version.** Do not
edit it by hand; see [releasing.md](releasing.md).
