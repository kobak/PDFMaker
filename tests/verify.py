#!/usr/bin/env python3
"""Integration checks of the actual distributable, with generated test documents."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import unicodedata

from docx import Document
from docx.shared import Inches
from docx.oxml import OxmlElement
from PIL import Image, ImageDraw
from pypdf import PdfReader

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
version = (root/'VERSION').read_text().strip()
parser.add_argument('--app', type=Path, default=root/'dist'/version/'lite/PDF Maker.app')
parser.add_argument('--libreoffice', type=Path, help='External LibreOffice.app used for integration tests; does not change saved preferences')
parser.add_argument('--report', type=Path, default=root/'dist'/version/'release/verification-Lite.json')
args = parser.parse_args()
app = args.app.resolve()
binary = app/'Contents/MacOS/PDFConverter'
checks = []

def check(name, condition):
    if not condition:
        raise AssertionError(name)
    checks.append(name)

def run(languages, mode, *paths, success=True, application=args.libreoffice):
    command = [str(binary), '-AppleLanguages', '(' + ','.join(languages) + ')']
    if application is not None:
        command += ['--libreoffice', str(application.resolve())]
    result = subprocess.run(command + [mode, *map(str, paths)], capture_output=True, text=True, timeout=100)
    if (result.returncode == 0) != success:
        raise AssertionError((result.returncode, result.stdout, result.stderr))
    return json.loads(result.stdout)

info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
bundled = info.get('PDFMakerEngineMode') == 'bundled'
check('Release version matches VERSION', info['CFBundleShortVersionString'] == (root/'VERSION').read_text().strip())
check('English fallback and Hungarian support declared',
      info['CFBundleDevelopmentRegion'] == 'en' and info['CFBundleLocalizations'] == ['en','hu'])
catalogs = {language:run([language], '--print-localization') for language in ['en','hu']}
en, hu = catalogs['en'], catalogs['hu']
check('English app display name', en['displayName'] == 'PDF Maker')
check('Hungarian app display name', hu['displayName'] == 'PDF-készítő')
check('Translation catalogs have identical keys', en['strings'].keys() == hu['strings'].keys())
check('Every translation is nonempty', all(en['strings'].values()) and all(hu['strings'].values()))
formats = lambda value:re.findall(r'%(?:ld|@)',value)
check('All translated format parameters match', all(formats(v)==formats(hu['strings'][k]) for k,v in en['strings'].items()))
for preferences, expected in [(['en-US'],'en'),(['en-GB'],'en'),(['hu-HU'],'hu'),
                              (['de'],'en'),(['fr'],'en'),(['en','hu'],'en'),(['hu','en'],'hu')]:
    value = run(preferences,'--print-localization')
    check(','.join(preferences)+' resolves to '+expected, value['preferredLocalizations'][0] == expected)
check('English singular page', en['samples']['onePage'] == 'Done · 1 page · sample.pdf')
check('English plural pages', en['samples']['manyPages'] == 'Done · 3 pages · sample.pdf')
check('English singular progress', en['samples']['onePending'] == 'Processing · 1 document left')
check('English plural progress', en['samples']['manyPending'] == 'Processing · 3 documents left')
check('Hungarian dynamic status', hu['samples']['manyPending'] == 'Feldolgozás · 3 dokumentum van hátra')
check('Formatted messages contain no placeholders', all('%' not in v for c in catalogs.values() for v in c['samples'].values()))

with tempfile.TemporaryDirectory(prefix='pdfmaker-test-') as temporary:
    folder = Path(temporary)
    docx = folder/'Árvíztűrő próba.docx'
    doc = docx.with_suffix('.doc')
    document = Document()
    document.add_heading('Árvíztűrő tükörfúrógép',0)
    document.add_paragraph('Magyar ékezetek: áéíóöőúüű ÁÉÍÓÖŐÚÜŰ.')
    table = document.add_table(rows=2,cols=2)
    table.style = 'Table Grid'
    for cell,value in zip([c for row in table.rows for c in row.cells],['Tétel','Érték','Alma','450 Ft']):
        cell.text = value
    equation = OxmlElement('m:oMath')
    fraction = OxmlElement('m:f')
    for tag,text in [('m:num','1'),('m:den','2')]:
        element = OxmlElement(tag); run_element = OxmlElement('m:r'); value = OxmlElement('m:t')
        value.text = text; run_element.append(value); element.append(run_element); fraction.append(element)
    equation.append(fraction)
    document.add_paragraph('Word-képlet: ')._p.append(equation)
    image = Image.new('RGB',(300,90),'#edf5ff')
    drawing = ImageDraw.Draw(image)
    drawing.rectangle((20,20,70,70),fill='#2368d8')
    drawing.ellipse((110,20,160,70),fill='#e93d48')
    image.save(folder/'figure.png')
    document.add_picture(str(folder/'figure.png'),width=Inches(3))
    document.sections[0].header.paragraphs[0].text = 'PDF Maker test'
    document.add_page_break()
    document.add_heading('Második oldal',1)
    document.add_paragraph('A kifejezett oldaltörés megmarad.')
    document.save(docx)
    engine_status = run(['en'], '--print-engine')
    engine = Path(engine_status['executable'])
    check('Configured conversion engine is available', engine_status['found'] and engine.is_file())
    conversion = subprocess.run([str(engine),'-env:UserInstallation='+(folder/'profile').as_uri(),
        '--headless','--nologo','--norestore','--convert-to','doc:MS Word 97','--outdir',str(folder),str(docx)],
        capture_output=True,text=True,timeout=90)
    check('Real legacy DOC fixture generated', conversion.returncode == 0 and doc.exists())
    inputs = {p:hashlib.sha256(p.read_bytes()).hexdigest() for p in [docx,doc]}
    original_pdf = docx.with_suffix('.pdf')
    original_pdf.write_bytes(b'Existing PDF must never be overwritten.')
    original_digest = hashlib.sha256(original_pdf.read_bytes()).hexdigest()
    outputs = []
    for language in ['en','hu']:
        values = run([language],'--convert',docx,doc)
        check(language+': DOC and DOCX each produce two pages',all(r.get('pages')==2 for r in values))
        for value in values:
            pdf = PdfReader(value['output'])
            text = '\n'.join(p.extract_text() for p in pdf.pages)
            check(language+': Hungarian text and table retained', 'Árvíztűrő' in text and '450 Ft' in text)
            check(language+': explicit page break retained','Második oldal' in pdf.pages[1].extract_text())
            check(language+': embedded image retained',any(len(p.images)>0 for p in pdf.pages))
            check(language+': Word equation label retained','Word-képlet' in text)
            if Path(value['input']).suffix == '.docx':
                check(language+': DOCX fraction text retained','1' in text and '2' in text)
            # Legacy DOC stores this equation as a vector graphic. Its digits
            # are visible in a rendered PDF but are not extractable text.
        outputs.extend(values)
    check('Every conversion has a distinct destination',len({r['output'] for r in outputs})==4)
    check('Existing PDF is unchanged', hashlib.sha256(original_pdf.read_bytes()).hexdigest()==original_digest)
    check('Word originals are unchanged',all(hashlib.sha256(p.read_bytes()).hexdigest()==digest for p,digest in inputs.items()))
    check('PDFs saved beside their originals',all(Path(r['output']).parent==folder for r in outputs))
    check('Filename collision numbering begins at 2',
          unicodedata.normalize('NFC',Path(outputs[0]['output']).name)=='Árvíztűrő próba (2).pdf')

    empty=folder/'empty.docx'; empty.touch()
    damaged=folder/'damaged.docx'; damaged.write_bytes(b'PK\x03\x04invalid')
    disguised=folder/'disguised.doc'; disguised.write_bytes(b'%PDF-1.7 not a Word file')
    unsupported=folder/'unsupported.txt'; unsupported.write_text('Not a Word document.')
    missing=folder/'missing.docx'
    for language in ['en','hu']:
        values = run([language],'--convert',empty,damaged,disguised,unsupported,missing,success=False)
        check(language+': all invalid inputs fail without output',all(r.get('error') and not r.get('output') for r in values))
        check(language+': file type error is translated', values[3]['error']==catalogs[language]['strings']['error.file_type'])
        check(language+': damaged file error is translated',values[1]['error']==catalogs[language]['strings']['error.conversion'])
        check(language+': missing file error is translated',values[4]['error']==catalogs[language]['strings']['error.unreadable'])
    check('Invalid inputs produce no PDFs',all(not p.with_suffix('.pdf').exists() for p in [empty,damaged,disguised,unsupported,missing]))
    if not bundled:
        for language in ['en','hu']:
            value = run([language], '--convert', docx, success=False, application=folder/'Not Installed.app')[0]
            check(language+': missing LibreOffice has a translated installation hint',
                  value['error'] == catalogs[language]['strings']['error.engine_missing'])
        value = run(['en'], '--print-engine', success=False, application=folder/'Not Installed.app')
        check('Invalid explicit location never falls back to another app', value['mode']=='external' and not value['found'])
    special=folder/"Upper 'quote' $name;.DOCX"; special.write_bytes(docx.read_bytes())
    check('Uppercase extension and shell metacharacters are literal',run(['en'],'--convert',special)[0].get('pages')==2)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        parallel=list(pool.map(lambda _:run(['en'],'--convert',docx)[0],range(2)))
    check('Concurrent conversions never overwrite each other',len({r['output'] for r in parallel})==2)

subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
check('Deep strict code signature verification',True)
engine_info=plistlib.loads((engine.parents[2]/'Contents/Info.plist').read_bytes())
engine_config=json.loads((root/'scripts/engine.json').read_text())
if bundled:
    check('Official bundled engine version matches pinned provenance',engine_info['CFBundleShortVersionString']==engine_config['version'])
    check('Original embedded license notices preserved',all((app/'Contents/Resources/ConverterEngine.app/Contents/Resources'/p).exists() for p in ['LICENSE','NOTICE']))
else:
    check('Lite uses an external engine', engine_status['mode']=='external' and not str(engine).startswith(str(app)+'/'))
    check('No LibreOffice runtime is packaged', not (app/'Contents/Resources/ConverterEngine.app').exists())
    app_bytes = sum(p.stat().st_size for p in app.rglob('*') if p.is_file() and not p.is_symlink())
    check('Lite application is smaller than 5 MiB', app_bytes < 5*1024*1024)
with tempfile.TemporaryDirectory(prefix='pdfmaker-locator-build-') as temporary:
    locator_test = Path(temporary)/'locator-checks'
    subprocess.run(['xcrun','swiftc','-swift-version','5','-framework','AppKit',
                    str(root/'src/LibreOfficeLocator.swift'),str(root/'tests/locator.swift'),'-o',str(locator_test)],check=True)
    locator_results = json.loads(subprocess.check_output([str(locator_test)],text=True))
    checks.extend(locator_results['checks'])
check('Icon preview is exactly 1024 square',Image.open(root/'assets/icon.png').size==(1024,1024))
report={
    'version':info['CFBundleShortVersionString'],'checks_passed':len(checks),'checks':checks,
    'engine_mode':'bundled' if bundled else 'external','engine_version_tested':engine_info['CFBundleShortVersionString'],
    'supported_languages':['en','hu'],'default_language':'en',
    'interactive_ui_verified':False,'apple_notarized':False,
    'interactive_ui_limitation':'No interactive GUI check: Computer Use permission was unavailable.'
}
args.report.parent.mkdir(parents=True,exist_ok=True)
args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
