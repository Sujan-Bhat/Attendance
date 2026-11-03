import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

void downloadWeb(Uint8List bytes, String filename, {String? mimeType}) {
  // An empty type matches the browser default for Blob, so passing '' when no
  // mimeType is supplied preserves the previous behaviour.
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType ?? ''),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
