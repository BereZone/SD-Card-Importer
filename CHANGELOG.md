# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The app version is now shown at the bottom of the sidebar, so you can tell at
  a glance which build you are running.

### Fixed

- The interface no longer freezes while each file is transferred. Copying and
  scanning ran on the main thread despite being dispatched to background tasks,
  so the window stopped responding for the duration of every file and only
  recovered between them.
- Memory during an import no longer grows with file size. Copy buffers
  accumulated in a single autorelease pool for the duration of each file, so
  peak memory tracked the largest file one-for-one — measured at +2058 MB while
  copying a 2 GB file, now +2.8 MB.
- Long imports no longer slow down as they progress. Appending an Activity Log
  line compared the entire log array, making a large import quadratic in the
  number of files.
- Thumbnails are no longer served at the wrong size. The cache keyed on file URL
  alone, so a 24 pt thumbnail generated for the table view was handed back to
  the 200 pt grid view.

### Changed

- Transfers are substantially faster. Files now stream in 8 MB blocks instead of
  1 MB, and reading overlaps writing so the card keeps streaming rather than
  sitting idle during every write. Measured on a UHS-II V60 card: importing to
  an external exFAT drive went from about 192 MB/s to about 246 MB/s, and to an
  internal disk from about 229 MB/s to about 247 MB/s. Both now run at the
  card's own read limit, which is as fast as the hardware allows.
- Copies are noticeably faster when verification is off. Every copy was
  checksummed even when nothing read the result, roughly halving throughput on
  fast cards for a value that was discarded. Verified copies and moves between
  volumes still checksum, and still refuse to delete a source that has not been
  confirmed.
- The thumbnail cache is capped at a 256 MB decoded-bitmap budget and is cleared
  when the file list is replaced, instead of growing until the system forced a
  purge.
- The Activity Log retains the most recent 2000 lines rather than every line for
  the life of the session.
- File transfers bypass the page cache, so importing a large card no longer
  displaces other cached data on the system.
- Transfer progress updates are throttled to a 0.5% / 100 ms interval, down from
  one update per megabyte copied.

## [1.0.0] - 2025-11-18

### Added

- Initial release.

[Unreleased]: https://github.com/BereZone/SD-Card-Importer/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/BereZone/SD-Card-Importer/releases/tag/v1.0.0
