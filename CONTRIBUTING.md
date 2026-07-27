# Contributing

Thanks for your interest in the SD Card File Importer. This document covers the
conventions the project follows and what a change needs before it can merge.

See [docs/development.md](docs/development.md) to get a working build, and
[docs/releasing.md](docs/releasing.md) for how versions ship.

## Conventions

The project follows three standards.

### Conventional Commits

Commit subjects follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):

```
type(scope): description
```

Written in the imperative mood, lowercase, with no trailing period. The scope is
optional but useful — `import`, `scanner`, `ui`, `thumbnails`, `profiles`.

| Type | Use for |
| --- | --- |
| `feat` | A new user-facing capability |
| `fix` | A bug fix |
| `perf` | A change that improves performance without changing behaviour |
| `refactor` | A change that neither fixes a bug nor adds a feature |
| `docs` | Documentation only |
| `test` | Adding or correcting tests |
| `build` | Build system, Xcode project settings, dependencies |
| `ci` | GitHub Actions workflows |
| `chore` | Anything else that does not affect the app |

Examples from this repository:

```
fix(import): bound memory growth during file transfer
feat(profiles): add Panasonic card layout detection
docs: describe the release process
```

A breaking change takes an `!` before the colon and a footer:

```
feat(import)!: replace folder template syntax

BREAKING CHANGE: {Camera} placeholders are now {camera}. Existing
templates need updating in Settings.
```

The body is where the reasoning goes. Explain why the change was needed and what
you measured, not what the diff already shows.

### Keep a Changelog

Every user-visible change gets an entry in `CHANGELOG.md` under `## [Unreleased]`,
in the same pull request as the change itself.

Use only the six headings the standard defines: `Added`, `Changed`, `Deprecated`,
`Removed`, `Fixed`, `Security`.

Write entries for the person using the app, not the person reading the diff.
"Memory during an import no longer grows with file size" is useful; "refactored
copyFile" is not.

Purely internal changes — refactors, CI, tests — do not need an entry.

### Semantic Versioning

Versions are `MAJOR.MINOR.PATCH` per [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html):

- **MAJOR** — an incompatible change. For an app, that means something a user
  relied on stops working the way it did: a settings format change, removed
  behaviour, a different default that changes where files land.
- **MINOR** — new functionality, backwards compatible.
- **PATCH** — backwards-compatible bug fixes.

Git tags are the version prefixed with `v`: `v1.2.3`. The release workflow
rejects tags that are not valid semver, so `v1.2` and `v1.2.3.4` will fail.

Never edit version numbers by hand. `MARKETING_VERSION` in the Xcode project is
the single source of truth, and `make bump` is what changes it.

## Making a change

1. Get a build working — see [docs/development.md](docs/development.md).
2. Make the change. Match the surrounding code's naming and comment density.
3. Run `make build`. If a test target exists, `make test`.
4. Add a `CHANGELOG.md` entry under `## [Unreleased]` if the change is
   user-visible.
5. Commit with a Conventional Commit subject.
6. Open a pull request and fill in the template.

## Branching

`main` is currently unprotected and the maintainer pushes to it directly. If the
project takes on more contributors, direct pushes should be restricted through a
GitHub ruleset requiring pull requests and a passing CI run. Until then, outside
contributions go through pull requests against `main`.

## Attribution

Commits carry the author's own name. Do not add `Co-Authored-By` trailers for AI
assistants or "generated with" footers.
