#!/usr/bin/env python3
"""Create a compressed drag-to-Applications disk image without UI scripting."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
version = (root/'VERSION').read_text().strip()
parser.add_argument('--app', type=Path, default=root/'dist'/version/'lite/PDF Maker.app')
parser.add_argument('--output', type=Path, default=root/'dist'/version/'release')
args = parser.parse_args()
import plistlib
info = plistlib.loads((args.app/'Contents/Info.plist').read_bytes())
if info.get('CFBundleShortVersionString') != version:
    raise SystemExit('Application version does not match VERSION')
bundled = info.get('PDFMakerEngineMode') == 'bundled'
variant = 'Full' if bundled else 'Lite'
args.output.mkdir(parents=True, exist_ok=True)
image = args.output / f'PDFMaker-{version}-{variant}-arm64.dmg'
if image.exists():
    raise SystemExit('Existing release image will not be overwritten: ' + str(image))
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(args.app)], check=True)
with tempfile.TemporaryDirectory(prefix='pdfmaker-dmg-') as folder:
    stage = Path(folder)
    subprocess.run(['ditto', str(args.app), str(stage/'PDF Maker.app')], check=True)
    (stage/'Applications').symlink_to('/Applications', target_is_directory=True)
    (stage/'Read Me.txt').write_text(
        'PDF Maker ' + version + ' ' + variant + '\n\n'
        'Drag PDF Maker to Applications. Then open it and drop your Word files into its window.\n'
        'PDFs are saved next to the original files. English and Hungarian are supported.\n\n'
        + ('Includes the LibreOffice conversion engine.\n\n' if bundled else
           'Requires LibreOffice to be installed separately in Applications.\n'
           'For a custom location, use File > Locate LibreOffice in PDF Maker.\n'
           'LibreOffice download: https://www.libreoffice.org/download/\n\n') +
        'Apple Silicon (M1 or newer), macOS 13 or newer.\n'
        'This build is ad-hoc signed and is not notarized by Apple.\n'
        'macOS may require manual approval when opening an app downloaded from the internet.\n\n'
        'Magyarul: húzd a PDF Maker alkalmazást az Applications mappába, majd nyisd meg.\n'
        'A Word-fájlokat az ablakba vagy az alkalmazás ikonjára húzhatod.\n'
        'Az elkészült PDF az eredeti dokumentum mellé kerül.\n\n'
        + ('' if bundled else 'A kis változathoz külön telepített LibreOffice szükséges.\n'
           'Egyéni hely: Fájl > LibreOffice megkeresése…\n\n') +
        'https://github.com/kobak/PDFMaker\n'
    )
    subprocess.run(['hdiutil', 'create', '-volname', 'PDF Maker', '-srcfolder', str(stage),
                    '-format', 'UDZO', '-fs', 'HFS+', '-imagekey', 'zlib-level=9', str(image)], check=True)
subprocess.run(['hdiutil', 'verify', str(image)], check=True)
digest = hashlib.sha256(image.read_bytes()).hexdigest()
checksum = args.output / 'SHA256SUMS.txt'
checksum.write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n'
                          for p in sorted(args.output.glob('*.dmg'))))
print(image)
print(checksum)
