# SD Card File Importer

A macOS app for getting footage off camera cards and into a folder structure you
can actually navigate.

It detects mounted camera cards, recognises the directory layouts used by Canon,
Nikon, Sony, Fujifilm, Panasonic and DJI, reads real capture dates from EXIF
rather than trusting card timestamps, and files everything into a folder template
you control. Copies are checksummed as they stream, so a verified import tells
you the bytes on disk match the bytes on the card.

## Requirements

macOS 14.0 or later.

## Install

Download the latest build from
[Releases](https://github.com/BereZone/SD-Card-Importer/releases).

Release builds are not code-signed, so macOS will refuse to open the app on the
first try. Right-click the app and choose **Open**, then confirm.

To build from source instead, see [docs/development.md](docs/development.md).

## Documentation

- [Development](docs/development.md) — building, running, project layout
- [Releasing](docs/releasing.md) — versioning and publishing a release
- [Contributing](CONTRIBUTING.md) — conventions and how to submit a change
- [Changelog](CHANGELOG.md) — what changed in each version

## License

[MIT](LICENSE)
