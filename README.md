# SD Card File Importer

A macOS app for getting footage off camera cards and into a folder structure you
can actually navigate.

It detects mounted camera cards, recognises the directory layouts used by Canon,
Nikon, Sony, Fujifilm, Panasonic and DJI, reads real capture dates from EXIF
rather than trusting card timestamps, and files everything into a folder template
you control. Copies are checksummed as they stream, so a verified import tells
you the bytes on disk match the bytes on the card.

![The SD Card File Importer window: a card list on the left showing capacity, a
contact sheet of selected photos and video in the middle, and a plan bar along
the bottom reading "Untitled → T7/A7C Videos/2026/08_August/05" with Options,
History and Import controls.](docs/images/preview.png)

## Requirements

macOS 14.0 or later.

## Install

Download the latest build from
[Releases](https://github.com/BereZone/SD-Card-Importer/releases).

Release builds are signed ad-hoc rather than with a Developer ID, and are not
notarized, so macOS blocks them on first launch. After moving the app to
Applications, either right-click it and choose **Open** and confirm, or run:

```sh
xattr -dr com.apple.quarantine "/Applications/SD Card File Importer.app"
```

The command removes the download flag and always works; the right-click route
depends on your Gatekeeper settings.

To build from source instead, see [docs/development.md](docs/development.md).

## Documentation

- [Development](docs/development.md) — building, running, project layout
- [Product](docs/product.md) — who the app is for and what it promises them
- [Design](docs/design.md) — the visual system and the reasoning behind it
- [Releasing](docs/releasing.md) — versioning and publishing a release
- [Contributing](CONTRIBUTING.md) — conventions and how to submit a change
- [Changelog](CHANGELOG.md) — what changed in each version

## License

[MIT](LICENSE)
