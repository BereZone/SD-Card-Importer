# Releasing

Releases are driven by git tags. Pushing a tag matching `v*` runs
`.github/workflows/release.yml`, which validates the tag, builds the app, and
opens a **draft** release for you to review and publish.

Nothing is published automatically. The draft waits for you.

## Version numbering

The project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html):

| Bump | When |
| --- | --- |
| MAJOR | A user-visible behaviour someone relied on changes or goes away — settings format, where files land, removed options |
| MINOR | New capability, everything existing keeps working |
| PATCH | Bug fixes only |

`MARKETING_VERSION` in `SD Card File Importer.xcodeproj/project.pbxproj` is the
single source of truth. The tag must match it exactly, and the release workflow
fails if they disagree — that check exists so a shipped build can never report a
different version than its release page.

## Releasing

### 1. Check the tree is ready

```sh
make release-check
```

Verifies `MARKETING_VERSION` is valid semver, `CHANGELOG.md` has a matching
section, and the working tree is clean. These are the same checks the workflow
runs, so passing locally means the tag will not bounce.

### 2. Bump the version

```sh
make bump VERSION=1.1.0
```

Pass the bare version — no `v` prefix. The target confirms the change before
writing, rejects malformed input, and if `MARKETING_VERSION` already equals the
target it reports that and exits successfully rather than erroring, so retrying
an interrupted bump is safe.

### 3. Move the changelog entries

Open `CHANGELOG.md` and move everything under `## [Unreleased]` into a new
section:

```markdown
## [Unreleased]

## [1.1.0] - 2026-07-26

### Fixed

- ...
```

Update the link definitions at the bottom of the file too. This section becomes
the release body verbatim, so write it for users.

### 4. Commit

```sh
git add -A
git commit -m "chore(release): 1.1.0"
```

### 5. Tag

```sh
make tag
```

Reads the version from the project, refuses to overwrite an existing tag, and
creates an **annotated** tag with the changelog section as its message.
Annotated matters — `git push --follow-tags` only pushes annotated tags.

### 6. Push

```sh
git push --follow-tags
```

### 7. Review and publish

The workflow builds and opens a draft release. Check the notes and download the
zip to confirm it launches, then publish from the GitHub UI.

## Undoing a release

```sh
make untag VERSION=1.1.0
```

Confirms before deleting, removes the tag locally and on the remote, then checks
whether a GitHub release exists and asks whether to delete that too.

You can usually leave the release in place: the release action upserts, so
re-pushing the same tag updates the existing draft rather than failing.

## What the workflow checks

Each of these fails the run rather than producing a bad release:

1. The tag is strict `vMAJOR.MINOR.PATCH`, with optional prerelease and build
   metadata. `v1.0` and `vv1.0.0` are rejected.
2. `MARKETING_VERSION` equals the tag version.
3. `MARKETING_VERSION` is identical across all build configurations — Debug and
   Release are separate entries in the Xcode project and drift easily.
4. `CHANGELOG.md` contains a `## [VERSION]` section and it is not empty.
5. The app builds and the `.app` bundle exists where expected.

A tag containing a hyphen (`v1.1.0-beta.1`) is marked as a prerelease
automatically.

## Code signing

CI has no signing certificate, so the workflow signs the bundle **ad-hoc**
(`codesign --force --deep --sign -`) after building.

That step is not cosmetic. Building with `CODE_SIGNING_ALLOWED=NO` leaves only
the ad-hoc signature the linker applies to the executable, with no
`_CodeSignature/CodeResources` for the bundle. Since the bundle does contain
resources, that combination is a structurally *invalid* signature rather than a
merely untrusted one, and macOS reports the download as **"damaged and can't be
opened"** — which right-click > Open cannot bypass. Signing the whole bundle
ad-hoc produces a valid signature, so it degrades to the ordinary
unidentified-developer prompt instead. The workflow fails the release if
`CodeResources` is missing afterwards.

Ad-hoc signing is still not a Developer ID and still not notarized, so
Gatekeeper blocks first launch either way. The release notes tell users to run:

```sh
xattr -dr com.apple.quarantine "/Applications/SD Card File Importer.app"
```

To ship builds that open with no warning at all you would need a Developer ID
certificate, its password, and an App Store Connect API key in repository
secrets, then import the certificate into a temporary keychain and run
`notarytool` after the build. That is a meaningful amount of setup and is not
currently done.

## Migrating from the `v1.0` tag

The existing `v1.0` tag predates this process and is not valid semver — the
release workflow would reject it. The first release under this process should be
`v1.0.0` or later. Leave `v1.0` alone as historical record; nothing depends on
it.
