# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Options, History, and Import are now three separate toolbar buttons rather
  than items that folded into an overflow menu, and Import is filled in the
  accent colour so it never reads as a peer of the two buttons that just open
  panels. It turns red when the operation would delete originals, and while an
  import is running it becomes a red Cancel.
- Thumbnails keep the shape of their source. Landscape frames are wider than
  tall and portrait frames are taller than wide, instead of every image being
  cropped to a square.
- Verification is off by default again. The indicator light makes its state
  visible, so the default no longer has to carry that job.

### Added

- An indicator light for checksum verification in the plan bar, lit while
  verification is armed and pulsing while an import runs. It shows a lock when a
  Move forces it on, and always carries a text label so the state never depends
  on colour alone.

### Fixed

- The Options button did nothing. It was placed in a toolbar that used a
  `.principal` item, which pushed the trailing buttons into an overflow menu;
  a popover anchored to a button inside that menu has nothing to present from.
  Both the collapsing and the dead button are gone.

## [2.0.0] - 2026-08-02

A rebuild of the interface around the two things that matter when you empty a
card: what you are about to move, and where it is going. The import engine is
unchanged — the same verified copy, camera-profile routing, and EXIF-first
foldering — but almost everything you look at while it runs is new.

### Changed

- The main window has been rebuilt around the contact sheet. Photographs and
  video are shown at a size where you can recognise them, up to 320pt, instead
  of a 32pt icon that could not be enlarged. Grid, list, and by-day views
  replace the four near-identical file-browser layouts.
- The sidebar now lists your cards, not app sections. Selecting a card filters
  the contact sheet to it and reveals that card's photo and video folder
  assignment in place.
- A plan bar runs along the bottom of the window at all times. Before an import
  it states the operation, the source card, the resolved destination path, the
  file count and the total size. During one it carries progress, speed and time
  remaining. Afterwards it reports the outcome, including whether the copies
  were verified, with Show in Finder and Retry Failed.
- Every file now shows where it will actually land, resolved from your folder
  template, the card's assignment, the detected camera and the file's EXIF date.
  This was previously not visible anywhere; the only preview in the app showed a
  hardcoded example that ignored the real card.
- Settings and Appearance moved out of the sidebar into a proper Settings window,
  so ⌘, works. Import options moved into a toolbar popover next to the button
  that uses them.
- The Activity Log became a History inspector you open from the toolbar. Entries
  carry timestamps and a real severity, and can be filtered to problems only or
  exported to a file.
- The window minimum dropped from 1000×650 to 820×520 so the app fits on a 13"
  laptop beside another window.
- The interface now uses standard macOS materials, controls, and your own accent
  colour, replacing the gradient headings, translucent cards, hardcoded blue and
  purple, and hover-scaling buttons. Light and dark are both first-class.
- "Bucket" is now "folder" throughout, and the default folder names are generic
  starting points rather than one person's camera bag.
- Empty states now distinguish "no card inserted" from "this card has no
  importable files". They previously shared the headline "Waiting for Media", so
  a scanned card that yielded nothing told you to insert a card you had already
  inserted.

### Added

- Full keyboard control: ⌘R refresh, ⇧⌘R rescan, ⌘A and ⇧⌘A select all and none,
  ⌘⏎ start, ⌘. cancel, ⇧⌘D choose destination — all also in a new Import menu.
  The app previously had no keyboard shortcuts at all.
- Accessibility support throughout. Every control has a name, icon-only buttons
  have tooltips, the progress bar reports its percentage, the capacity bar
  reports its state, and Quick Look is reachable without a mouse. The app
  previously contained no accessibility information of any kind and could not be
  operated with VoiceOver.
- Import history can be exported to a text file.

- An import can now be cancelled. While files are transferring, Start Import
  becomes Cancel Import, which stops after the file in flight rather than
  leaving Force Quit as the only way out.
- The Actions card now states what Start Import is about to do before you press
  it — the operation, the file count, the total size, and the destination
  folder. The destination was previously not shown anywhere in the main window.
- Moving files off a card now asks for confirmation, naming the card and the
  number of files, and saying that each original is deleted only after its copy
  has been verified. Copy and Dry Run still start without interruption.

### Fixed

- Inserting or ejecting any volume during an import no longer empties the file
  list the import is working through. The tally at the end read the live list,
  so pulling a card mid-import reported nonsense like "Done. Imported 137/0".
- Start Import is now disabled when no files are selected, instead of running
  and reporting "Done. Imported 0/0".
- The progress bar no longer stays frozen at 100% after a scan or a finished
  import. It appears only while an import is actually running.
- Verification is now on by default, and preview mode is off. The shipped
  defaults previously did the opposite, so a new user's first import copied
  nothing and reported "Done. Imported 0/482", and an import that did run was
  not verified — the one thing the app exists to guarantee.
- Custom folder names are now sanitised. "2026/Wedding" silently created a
  nested folder and ".." was accepted unchecked.
- Long filenames now truncate in the middle. Camera filenames differ at the end,
  so tail truncation hid the only part that distinguished one file from another.
- The thumbnail size slider now only sizes thumbnails. It was wired into spacing
  arithmetic in eight unrelated places, including a card with no thumbnails in
  it, and produced negative spacing at its lowest setting.

### Removed

- The "Window Translucency (Glass Effect)" setting, which never used a
  visual-effect material and produced no glass.
- The "UI Density" setting, which was driven by the thumbnail size slider rather
  than by anything the user set.
- The table view. Grid, list, and by-day remain; the table duplicated the list
  without adding anything.
- The developer "Debug" scan toggle, which shipped in the main window.
- `make build` now fails when the build fails. The recipe piped `xcodebuild`
  through `grep`, so the exit status came from `grep` and a broken toolchain or
  a compile error still printed "Build finished." and exited 0. `make debug` and
  `make test` had the same flaw. A missing Xcode toolchain now reports the
  `xcode-select` command that fixes it.

## [1.1.0] - 2026-07-28

### Added

- The app version is now shown at the bottom of the sidebar, so you can tell at
  a glance which build you are running.

### Fixed

- Downloaded builds no longer report as "damaged and can't be opened". The app
  bundle is now signed, so macOS treats it as an ordinary unsigned download you
  can allow, rather than a corrupted one it refuses outright.
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

[Unreleased]: https://github.com/BereZone/SD-Card-Importer/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/BereZone/SD-Card-Importer/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/BereZone/SD-Card-Importer/compare/v1.0...v1.1.0
[1.0.0]: https://github.com/BereZone/SD-Card-Importer/releases/tag/v1.0
