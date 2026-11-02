#!/usr/bin/env python3
"""Download and verify the pinned official LibreOffice Apple Silicon release."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / 'scripts/engine.json').read_text())
CACHE = ROOT / '.cache'
APP = CACHE / 'LibreOffice.app'

def fetch():
    CACHE.mkdir(exist_ok=True)
    if APP.exists():
        import plistlib
        info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
        if info.get('CFBundleShortVersionString') != CONFIG['version']:
            raise RuntimeError('Cached engine version does not match scripts/engine.json')
        return APP
    image = CACHE / ('LibreOffice-' + CONFIG['version'] + '-arm64.dmg')
    if not image.exists():
        temporary = image.with_suffix('.download')
        print('Downloading the official LibreOffice engine…', flush=True)
        try:
            with urllib.request.urlopen(CONFIG['url'], timeout=60) as response, temporary.open('wb') as output:
                shutil.copyfileobj(response, output)
            temporary.rename(image)
        finally:
            temporary.unlink(missing_ok=True)
    with image.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hashlib.sha256(stream.read()).hexdigest()
    if digest != CONFIG['sha256']:
        raise RuntimeError('LibreOffice download checksum mismatch; cached download was not used')
    with tempfile.TemporaryDirectory(prefix='pdfmaker-engine-') as directory:
        mount = Path(directory) / 'mount'
        subprocess.run(['hdiutil', 'attach', '-nobrowse', '-readonly', '-mountpoint', str(mount), str(image)], check=True)
        try:
            subprocess.run(['ditto', str(mount / 'LibreOffice.app'), str(APP)], check=True)
        finally:
            subprocess.run(['hdiutil', 'detach', str(mount)], check=True)
    return APP

if __name__ == '__main__':
    print(fetch())
