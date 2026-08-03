# Design

<!-- impeccable:design-schema 1 -->

The durable visual system for SD Card File Importer. Product truth lives in
[PRODUCT.md](PRODUCT.md); this file owns how the app looks and behaves.

## Direction contract

**THESIS.** The window is a contact sheet with a stated plan underneath it. This
app refuses the arrangement it currently ships — a grid of equal-weight cards
where the primary action is one quadrant of four — because in an ingest tool
exactly two things matter: what you are about to move, and where it is going.
Everything else is chrome or configuration and belongs in a toolbar, a popover,
or Settings.

**OWN-WORLD.** macOS convention played straight, at the craft level of Panic's
shell, Carbon Copy Cloner's explicitness, and Photo Mechanic's content density.
System materials and the user's own accent color; no invented palette, no
gradient type, no glass as decoration. Recognizable with all content removed by
its three-band structure: source list of cards, contact sheet, persistent plan
bar.

**STORY.** The user plugs in a card, sees their photographs at a size where they
can recognize them, reads one sentence saying what will happen and where, and
presses one button. Afterwards the same bar tells them it succeeded and that the
copies were verified.

**FIRST VIEWPORT.** Toolbar across the top with refresh and the view switcher.
Source list on the left listing physical cards with capacity. Contact sheet
filling the remaining width. A plan bar pinned to the bottom spanning the content
area, carrying `CARD → destination path`, counts and size, and the safety
statement on the left, with Options, History and the primary action on the
right.

**FORM.** macOS convention, taken deliberately as the standing exit rather than
rolled for. Craft bar: Panic (shell), Carbon Copy Cloner (risk), Photo Mechanic
(content). Confirmed by the user 2026-08-02.

## Color

**Strategy: Restrained.** System neutrals plus the user's accent color. The app
has no brand palette and must not invent one — it is a utility that sits beside
Lightroom, and a saturated identity would fight the photographs, which are the
actual content.

Appearance follows the system. Both light and dark are first-class: the desk
scene is often light, the field-at-night scene is dark. Neither is a default.

| Role | Token | Value |
|---|---|---|
| Accent, selection, progress | `Color.accentColor` | System accent — the user's choice, never overridden |
| Primary text | `.primary` | |
| Secondary text | `.secondary` | Never below 11pt, never under 60% opacity |
| Window ground | `Color(nsColor: .windowBackgroundColor)` | |
| Raised surface | `Color(nsColor: .controlBackgroundColor)` | Opaque. Never a translucent fill over a translucent ground |
| Separator | `Color(nsColor: .separatorColor)` | |
| Destructive / over-capacity | `.red` | One red only |
| Success / verified | `.green` | |
| Caution | `.orange` | |

Rules:

- No hardcoded RGB. The five literals in the old `Colors.swift` are removed.
- Semantic status colors (`.red`, `.green`, `.orange`) are the system's, so they
  adapt to appearance and to Increase Contrast automatically.
- Color never carries meaning alone. Over-capacity is red **and** labeled;
  verified is green **and** says "verified"; a failed row is red **and** carries
  an icon.
- Status text on a colored fill uses that hue's foreground, never white on a
  saturated chip. Badges are tinted background plus colored foreground.

## Type

System font throughout — SF Pro, via SwiftUI text styles. No `design: .rounded`;
it was decoration, and macOS system UI is not rounded. Monospaced digits on
anything that counts or measures, so numbers do not jitter while updating.

| Use | Style |
|---|---|
| Window/section titles | `.headline` |
| Body, list rows, controls | `.body` |
| Filenames in the contact sheet | `.caption` |
| Secondary metadata, counts | `.caption` + `.secondary` |
| Measurements (size, speed, ETA, %) | `.caption.monospacedDigit()` |

Every size comes from a text style so Dynamic Type works. `.system(size:)` with
a raw number is not used; the 9pt, 10pt, and 11pt literals in the old code are
gone. Filenames truncate with `.truncationMode(.middle)` — the distinguishing
part of a camera filename is at the end.

## Space

One scale, named, used everywhere. The old code used 15 distinct magnitudes with
no system.

| Token | Value | Use |
|---|---|---|
| `Metrics.tight` | 4 | Within a label group |
| `Metrics.snug` | 8 | Between related controls |
| `Metrics.regular` | 12 | Default control spacing |
| `Metrics.section` | 20 | Between distinct groups |
| `Metrics.gutter` | 16 | Window and pane insets |

Corner radius: `6` for controls and thumbnails, `10` for raised panels. Two
values, not five.

More space above a heading than below it. Tight within a group, generous
between groups.

## Structure

Three bands, always:

1. **Toolbar** — refresh and the view switcher (segmented). Nothing that must
   always be visible, because toolbar items collapse.
2. **Content** — `NavigationSplitView` with a source list of *cards* on the left
   and the contact sheet on the right. Settings and Appearance are not sidebar
   rows; they live in a `Settings` scene reached by ⌘,.
3. **Plan bar** — pinned to the bottom of the content area, always present.
   Left: the operation, the destination path, counts, size, and the safety
   statement; during an import the progress readout; after one the result.
   Right: Options, History, and the primary action.

Window minimum: **820×520**, so the app fits a 13" laptop beside another window.
The previous 1000×650 did not.

Panels are opaque `controlBackgroundColor` separated by hairlines and spacing.
No card carries a colored stroke or a colored shadow. Nested cards do not exist.

## Controls

- Standard SwiftUI controls throughout. There is no custom `ButtonStyle`; the
  primary action is `.borderedProminent` with a tint, which gets the platform's
  focus ring, pressed state, and appearance handling for free.
- `.borderedProminent` for the primary action, tinted accent normally and red
  when the operation deletes originals or when it is Cancel; `.bordered` for
  secondary; `.plain` only for genuine icon affordances, which always carry
  `.help()`.
- **The window toolbar holds only view controls** — refresh and the layout
  switcher. It is not trustworthy for anything that must always be visible: a
  `ToolbarItemGroup` collapses into an overflow `»` menu when space is tight,
  which also strands any popover anchored to a collapsed item, and a
  `.borderedProminent` button loses its fill once AppKit adopts it as a toolbar
  item. `.principal` placement makes both failures worse by pushing everything
  outward, and is never used.
- Options, History, and the primary action sit at the trailing end of the plan
  bar, bottom right, in that order. Owning that layout means they are always
  present, always labelled, and the action is beside the sentence that says what
  it will do.
- The primary action names what it will do — Preview when nothing will be
  written, Cancel while an import is running, Done when a result is showing —
  and stays in the same place while doing it. Only the label changes.
- Every icon-only control has an `.accessibilityLabel` and a `.help()` tooltip.
- Text fields use the platform field style and keep their focus ring. The old
  `.plain` field with a tinted fill read as disabled.
- Destructive actions use `role: .destructive` and are confirmed with a
  `confirmationDialog` that names the object at risk.

## Images

Thumbnails keep the aspect ratio of their source. `size` is the long edge; the
short edge follows from the image, so a landscape frame is wider than tall and a
portrait frame is taller than wide, and neither is cropped. Grid cells top-align
because their heights differ. The dense list is the one exception — at 28pt,
ragged rows cost more than orientation is worth, so it forces a square.

Before an image loads, its box is drawn at 3:2 — the aspect of most stills
cameras — so the grid does not visibly re-flow as thumbnails arrive.

## Status indication

Verification has a dedicated indicator light in the plan bar: lit green while
armed, unlit when off, with a halo only while an import is actually running. It
is an indicator, never a control, and it always carries a text label, so its
state never depends on colour alone. It appears wherever the operation is
described — the plan, and the progress readout.

## Motion

One authored moment: the contact sheet populating after a scan, and rows
resolving to a done state after import. Both are short, standard, and
interruptible. No hover-scale on buttons, no infinite pulse, no spring on
anything that reports state — an ingest tool must look calm while it works.

All motion respects `accessibilityReduceMotion`.

## States

Every surface defines all of: no card, card present but unscanned, scanning,
scanned with zero results, populated, importing, cancelled, failed, succeeded.
The two empty states never share copy — "no card inserted" and "card has no
importable files" are different problems with different fixes.

Errors name the problem and the recovery, in place, near their source. Failures
appear as an inline banner with a retry affordance, not as text in a log.

## Accessibility

Non-negotiable, and checked on every change:

- Every control has an accessible name. No `Toggle("")`.
- The whole primary flow is completable by keyboard: ⌘R refresh, ⌘A / ⇧⌘A
  select all and none, ⌘Return import, Escape cancel, Space to Quick Look.
- Focus is always visible, including on custom button styles.
- Progress and completion are announced (`.accessibilityValue`, and an
  announcement on finish).
- Text meets WCAG AA in both appearances.
- Severity is never carried by an emoji inside a string.

## Retired

These devices are removed and do not return: gradient-filled section headers,
`ModernCardStyle`'s colored stroke and colored shadow, `PremiumButtonStyle`'s
gradient and hover-scale, `design: .rounded` as the global type voice, the 5%
window gradient, the "Glass Effect" toggle that produced no glass, hardcoded RGB
brand colors, and the thumbnail slider doubling as a global density multiplier.
