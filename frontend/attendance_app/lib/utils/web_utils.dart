import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Save [bytes] to the browser's download folder as [filename].
///
/// This file is only reached through a conditional import
/// (`if (dart.library.js_interop)`), because importing `package:web`
/// unconditionally makes the whole app uncompilable for non-web targets such
/// as `flutter test`.
void downloadWeb(Uint8List bytes, String filename, {String? mimeType}) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType ?? ''),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  // Attach before clicking: detached anchors are ignored by some browsers.
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
