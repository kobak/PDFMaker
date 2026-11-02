# Third-party software

The default **Lite** package does not contain or redistribute LibreOffice.
It invokes the LibreOffice application already installed on the user's Mac,
using a separate temporary profile. That installation retains its own licenses.

Optional **Full** builds embed the official Apple Silicon build of **LibreOffice 26.8.2.2**
by The Document Foundation. Its source code is not modified. The bundle is
copied into `Contents/Resources/ConverterEngine.app` and signed as part of the
containing application. The embedded LibreOffice application's own documents,
notices and third-party licenses are retained.

- Official binary: https://download.documentfoundation.org/libreoffice/stable/26.8.2/mac/aarch64/LibreOffice_26.8.2_MacOS_aarch64.dmg
- SHA-256: `9f24fe83ab1ed5c95eb3df580119f32932f713e577feeac02bf619fb00749b55`
- Source revision: `9dea406ab7695df6325b11b0e19fdca8db4b7276`
- Corresponding source: https://git.libreoffice.org/core/+/9dea406ab7695df6325b11b0e19fdca8db4b7276
- Release source downloads: https://download.documentfoundation.org/libreoffice/src/26.8.2/
- Mozilla Public License 2.0: https://www.mozilla.org/MPL/2.0/

In Full builds, the embedded bundle retains its `Contents/Resources/LICENSE`, `LICENSE.html`,
`NOTICE` and other component notices. The wrapper's MIT license does not replace
any LibreOffice or third-party license. LibreOffice and The Document Foundation
are trademarks of their respective owners. PDF Maker is an independent utility
and is not an official LibreOffice product.
