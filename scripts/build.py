#!/usr/bin/env python3
"""Build the small app, or optionally include the LibreOffice conversion engine."""
import argparse
import pathlib
import plistlib
import shutil
import subprocess
import json

parser = argparse.ArgumentParser()
parser.add_argument('--bundle-engine', action='store_true', help='Build the large Full variant with the pinned official LibreOffice engine')
parser.add_argument('--engine', type=pathlib.Path, help='Official engine for a Full build; implies --bundle-engine')
parser.add_argument('--output', type=pathlib.Path, help='Build directory; defaults to dist/<version>/lite or full')
parser.add_argument('--sign-identity', default='-', help='Code signing identity; defaults to a local ad hoc signature')
args = parser.parse_args()
scripts = pathlib.Path(__file__).resolve().parent
root = scripts.parent
source = root / 'src'
version = (root / 'VERSION').read_text().strip()
bundled = args.bundle_engine or args.engine is not None
variant = 'full' if bundled else 'lite'
if bundled:
    if args.engine is None:
        from fetch_engine import fetch
        args.engine = fetch()
    engine_info = plistlib.loads((args.engine / 'Contents/Info.plist').read_bytes())
    engine_config = json.loads((scripts / 'engine.json').read_text())
    if engine_info['CFBundleShortVersionString'] != engine_config['version']:
        raise SystemExit('Engine version must match the pinned official release in scripts/engine.json')
output = (args.output or root / 'dist' / version / variant).resolve()
app = output / 'PDF Maker.app'
if app.exists():
    raise SystemExit(f'Existing bundle will not be overwritten: {app}')
macos = app / 'Contents/MacOS'
resources = app / 'Contents/Resources'
macos.mkdir(parents=True)
resources.mkdir()
if bundled:
    shutil.copytree(args.engine, resources / 'ConverterEngine.app', symlinks=True)
info = {
    'CFBundleName': 'PDF Maker',
    'CFBundleDisplayName': 'PDF Maker',
    'CFBundleIdentifier': 'hu.kobak.pdf-keszito',
    'CFBundleExecutable': 'PDFConverter',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': version,
    'CFBundleVersion': '4',
    'PDFMakerEngineMode': 'bundled' if bundled else 'external',
    'CFBundleIconFile': 'AppIcon',
    'LSMinimumSystemVersion': '13.0',
    'LSArchitecturePriority': ['arm64'],
    'NSHighResolutionCapable': True,
    'NSPrincipalClass': 'NSApplication',
    'CFBundleDevelopmentRegion': 'en',
    'CFBundleLocalizations': ['en', 'hu'],
    'CFBundleDocumentTypes': [{
        'CFBundleTypeName': 'Word Document',
        'CFBundleTypeRole': 'Viewer',
        'LSHandlerRank': 'Alternate',
        'LSItemContentTypes': ['com.microsoft.word.doc', 'org.openxmlformats.wordprocessingml.document'],
        'CFBundleTypeExtensions': ['doc', 'docx'],
        'CFBundleTypeMIMETypes': ['application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'],
    }],
}
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
for language in ['en', 'hu']:
    shutil.copytree(source / f'{language}.lproj', resources / f'{language}.lproj')
shutil.copy2(root / 'THIRD_PARTY_NOTICES.md', resources)
if bundled:
    shutil.copy2(scripts / 'engine.json', resources / 'engine-provenance.json')
subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-O', '-target', 'arm64-apple-macosx13.0',
                '-framework', 'AppKit', '-framework', 'PDFKit',
                str(source / 'Localization.swift'), str(source / 'LibreOfficeLocator.swift'),
                str(source / 'Converter.swift'), str(source / 'main.swift'),
                '-o', str(macos / 'PDFConverter')], check=True)
subprocess.run(['swift', str(scripts / 'make_icon.swift'), str(resources / 'AppIcon.icns')], check=True)
subprocess.run(['codesign', '--force', '--deep', '--sign', args.sign_identity, str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print(app)
