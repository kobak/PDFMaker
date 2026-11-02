<p align="center"><img src="assets/icon.png" width="160" alt="DOC document, arrow, PDF document"></p>

# PDF Maker

A small native Mac app that turns Word documents into PDFs. Drop your files in
the window, or use **Finder → Open With → PDF Maker**.

**[Download the latest DMG](https://github.com/kobak/PDFMaker/releases/latest)**

## Install

1. Download `PDFMaker-1.2.0-arm64.dmg` from [Releases](https://github.com/kobak/PDFMaker/releases).
2. Open the disk image and drag **PDF Maker** to **Applications**.
3. Open PDF Maker and drop one or more `.doc` or `.docx` files into its window.

Requires an **Apple Silicon Mac (M1 or newer), macOS 13 or newer**. This release
does not support Intel Macs. Microsoft Word and LibreOffice do not need to be
installed: the conversion engine is included.

The app is ad-hoc signed and **not notarized by Apple**. macOS may require manual
approval on first launch. See [Apple's instructions for opening downloaded apps](https://support.apple.com/102445).

## What it does

- Converts DOC and DOCX files locally, with no document uploads.
- Accepts several files through drag-and-drop, Open With, or Choose Files (`⌘O`).
- Saves each PDF beside its original. Existing PDFs are preserved:
  `report.pdf`, `report (2).pdf`, `report (3).pdf`.
- Reveals completed PDFs in Finder using the folder button.
- Supports **English** and **Hungarian**, including menus, progress and errors.

English is the default and fallback language; the interface follows macOS
language preferences. Choose an app-specific language in **System Settings →
General → Language & Region → Applications**.

Complex Word layouts and missing fonts can look different from Microsoft Word's
own PDF export. Password-protected, damaged and empty files produce an error.
The original folder must be writable. Each conversion has a 90-second timeout.

## Build from source

Requires macOS on Apple Silicon, Xcode Command Line Tools, and Python 3.9+.
The first build downloads and verifies the pinned official LibreOffice engine.

```sh
python3 scripts/build.py
python3 scripts/make_dmg.py
```

Artifacts are created in `dist/`. For an already downloaded official engine:

```sh
python3 scripts/build.py --engine /path/to/LibreOffice.app
```

`--sign-identity 'Developer ID Application: …'` accepts a local signing identity.
Developer ID signing and Apple notarization are separate from the default local
build. No signing keys or credentials are stored in this repository.

## Verify

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python tests/verify.py --app 'dist/PDF Maker.app'
```

The checks exercise both languages, English fallback, DOC and DOCX conversions,
page breaks, Hungarian text, corrupt files, original preservation and filename
collisions. `--convert` and `--print-localization` are command-line verification
entry points in the same executable used by the graphical application.

## Magyarul

Egyszerű, helyben működő Word → PDF alkalmazás Macre. Húzd a `.doc` vagy `.docx`
fájlokat az ablakba, vagy a Finderben válaszd a **Megnyitás ezzel → PDF Maker /
PDF-készítő** menüpontot. A PDF az eredeti mellé kerül; meglévő fájlt nem ír felül.
Angol és magyar felületet is tartalmaz. A nyelv a macOS alkalmazásonkénti
nyelvbeállításában választható. A DMG az Apple által nem notarizált kiadás.

## License

The native app and original icon artwork are available under the [MIT license](LICENSE).
The included LibreOffice engine retains its own licenses and notices; see
[Third-party notices](THIRD_PARTY_NOTICES.md) for the exact version, checksum
and corresponding source.
