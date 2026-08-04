# AGENTS.md

Guidance for AI agents and contributors working in this repository.

## Standards

This project follows three conventions. Apply them to every change.

- **[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)** —
  commit subjects are `type(scope): description`, imperative mood, no trailing
  period. Types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`,
  `ci`, `chore`. A breaking change takes `!` before the colon and a
  `BREAKING CHANGE:` footer.
- **[Keep a Changelog](https://keepachangelog.com/en/1.1.0/)** — every
  user-visible change gets an entry under `## [Unreleased]` in `CHANGELOG.md`,
  filed under one of `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`,
  `Security`. Those six are the only permitted headings.
- **[Semantic Versioning](https://semver.org/spec/v2.0.0.html)** —
  `MAJOR.MINOR.PATCH`. Git tags are the version prefixed with `v`, e.g.
  `v1.2.3`. The release workflow rejects anything that is not valid semver.

## Commit attribution

Commits carry the repository owner's name only. Do not add `Co-Authored-By`
trailers, "Generated with" footers, or any other AI attribution.

## Repository layout

- Documentation lives in `docs/`. Put new documents there, not at the root.
- `README.md` stays lean: what the app is, how to install it, and links into
  `docs/`. Detail belongs in `docs/`.
- Root-level files are limited to what tooling expects — `README.md`,
  `CHANGELOG.md`, `CONTRIBUTING.md`, `LICENSE`, `AGENTS.md`, `CLAUDE.md`,
  `Makefile`.

## Versioning

Never hand-edit version numbers. `MARKETING_VERSION` in
`SD Card File Importer.xcodeproj/project.pbxproj` is the single source of
truth, and `make bump` is the only thing that should change it. The release
workflow fails if the tag and `MARKETING_VERSION` disagree.

## Before you finish

- `make build` passes.
- `CHANGELOG.md` has an entry under `## [Unreleased]` if the change is
  user-visible.
- The commit subject is a valid Conventional Commit.
- Any document in `docs/` that describes the behaviour you changed has been
  updated in the same commit. `docs/development.md` in particular names types,
  methods and measured numbers; a change that moves or invalidates one of those
  must move the documentation with it. Stale documentation is worse than none,
  because it is trusted.
