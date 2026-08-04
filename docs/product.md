# Product

## Platform

macos

Native macOS app built in SwiftUI (`WindowGroup` + `NavigationSplitView`). Not
web, not iOS. Apple's macOS Human Interface Guidelines are the standard of
correctness for structure, controls, and keyboard behavior.

## Users

Solo photo and video creators who shoot with more than one camera — a mirrorless
body, a drone, an action camera, a phone — and who therefore end a shoot holding
several cards in different formats and folder layouts.

They are not IT people. They are comfortable with folders and file naming but
have no interest in the mechanics of copying. Defaults must generalize beyond
any single kit; the shipped bucket list is one person's cameras and is a
starting point, not a model of the audience.

## Product Purpose

Get files off camera cards and into an organized destination, and make the user
confident the transfer actually succeeded.

Success is a user who plugs in a card, presses one thing, and walks away knowing
where the files went and that nothing was lost. Failure is not a crash — failure
is finishing an import and still not being sure.

## Positioning

Two mechanisms a general-purpose file mover cannot truthfully claim:

- **Verified import.** Copies are re-read and checksum-compared against the
  source. On Move, a source file is deleted only after its copy verifies, and
  verification cannot be switched off in that mode.
- **Camera-profile routing.** The camera is identified from the card's DCIM
  layout, and files are routed per card and per media type — stills and footage
  from the same physical card can land in different destinations.

Supporting product knowledge that is part of the same position: EXIF
`DateTimeOriginal` outranks filesystem timestamps for date-based foldering,
undated files fall back to `Date.distantPast` rather than today so they cannot
silently land in the wrong folder, and camera proxy files (LRV, LRF, THM, `_T`)
are excluded from the import.

## Operating Context

Two confirmed scenes, and the design must serve both:

- **At a desk after a shoot.** Large display, unhurried, usually alongside
  Lightroom or an NLE. The app is one window among several, not the focus.
- **On a laptop in the field.** 13–14" screen, often tired and in a hurry,
  sometimes in bad light. This is the constraining case: the current 1000×650pt
  window minimum does not fit this scene and is a defect, not a preference.

Imports are long-running — tens of gigabytes is ordinary — so the app is
routinely left running while the user does something else.

## Capabilities and Constraints

Confirmed functionality:

- Detects mounted removable volumes; auto-refreshes and auto-scans on mount.
- Camera profiles for Canon, Sony, Nikon, Fujifilm, Panasonic, DJI, plus a
  generic fallback.
- Per-card, per-media-type destination assignment.
- Date filtering, including "Since Last Import".
- Template-driven folder structure and optional file renaming, with tokens.
- Free-space preflight before starting.
- Collision handling: same name and size is skipped; same name and different
  size is imported under a suffixed name.
- Copy or Move, dry-run preview, verify-after-copy, auto-eject, reveal in Finder.
- Cancellable mid-import.

Technical constraints:

- Sandboxed file access via security-scoped bookmarks; the user must grant
  access to each card, and a blocking system panel is currently how that is
  requested.
- macOS only; distributed as a signed but unnotarized download.
- No test target exists in the Xcode project yet.

Terminology — explicitly open:

- The app currently calls a destination folder assignment a **"bucket"**. This
  is borrowed from object storage and is not what photographers say. The user
  has confirmed it is **not** load-bearing and may be renamed.
- "Dry Run Mode" is likewise DevOps vocabulary, and its existence as a mode is
  an open question rather than a fixed capability.

Undecided, and not to be invented:

- Whether a persistent event log remains a visible surface at all. The user has
  confirmed the Activity Log is **not** load-bearing and may be demoted so that
  scan results, errors, and completion get their own homes.
- Whether a separate "Scan" action survives, given scanning is already automatic
  on mount, on refresh, and after access is granted.

## Brand Commitments

Name: **SD Card File Importer**. The app currently presents four different names
across the bundle, window title, sidebar, and in-window header; the bundle name
is the correct one and the others are drift, not identity.

No confirmed logo, palette, typeface, or voice guide. An app icon exists at
`SD Card File Importer/Assets.xcassets/AppIcon.appiconset/`. The existing
in-app visual language (gradient headings, glass cards, hover-scale buttons) is
**not** a brand commitment — the user has confirmed it was not deliberate and
should be replaced with native macOS.

**Standing preference (confirmed):** this product commits to macOS convention
played straight rather than an invented visual identity. The craft bar is set by
three named apps, each governing a different region of the window:

- **Panic (Transmit, Nova)** — the shell: a real toolbar with labeled controls, a
  source list of the objects the app is actually about, a persistent status bar,
  custom drawing only where AppKit genuinely falls short.
- **Carbon Copy Cloner** — the moment of risk: the operation stated as
  source → destination before it runs, safety framing in plain language, a real
  run history rather than a console.
- **Photo Mechanic** — the content area: the contact sheet is the window,
  thumbnails large and fast, selection as the primary verb, keyboard-driven.

This is a durable commitment, not a one-off styling choice. Future work matches
these apps' structure, density, and control vocabulary; it does not invent a
replacement idiom.

## Evidence on Hand

- Working implementation: `Strategies/` (camera profiles), `Services/`
  (scanning, importing, verification, permissions, thumbnails).
- `README.md`, `CHANGELOG.md`, `docs/development.md`, `docs/releasing.md`.
- Baseline design critique at `.impeccable/critique/` (14/40, 2026-08-01).

Absences that must not be fabricated: there are no users, no testimonials, no
download counts, no benchmarks, and no press. There is no pricing — the project
is open source under the repository's license. Any interface copy must not imply
otherwise.

## Product Principles

1. **State the plan before acting, and state the outcome after.** Every mistake
   this product can make is a destination mistake. The user should never have to
   reconstruct what happened from a log.
2. **Never destroy an original that has not been verified.** This is the promise
   the product is built on; it should be visible at the moment of risk, not
   discoverable afterwards in a log line.
3. **Defaults must be safe and must generalize.** The shipped configuration is
   a stranger's first experience, not the author's saved preferences.
4. **The photographs are the content.** An app about images that shows them at
   icon size has mistaken its own subject.
5. **Fit the field laptop, not just the desk.** The smaller scene is the real
   constraint; anything that only works at 1200pt wide has failed half the users.

## Accessibility & Inclusion

No product-specific standard has been set by the user, but the current state is
a confirmed defect: the codebase contains zero accessibility modifiers, no
keyboard shortcuts, and no focus indicators on its custom controls, which makes
the app inoperable with VoiceOver or Full Keyboard Access.

Baseline requirement for future work: every control carries an accessible name,
the primary flow is completable by keyboard alone, focus is always visible,
status changes are announced, and text meets WCAG AA contrast in both light and
dark appearance.
