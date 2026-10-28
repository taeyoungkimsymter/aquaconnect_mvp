import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// A file the user picked from the browser's file chooser.
class PickedFile {
  const PickedFile({required this.name, required this.contentType, required this.bytes});

  final String name;
  final String contentType;
  final Uint8List bytes;
}

/// Opens the browser's file chooser (any type, several at once). Resolves to
/// an empty list if the user cancels.
Future<List<PickedFile>> pickFiles() {
  final completer = Completer<List<PickedFile>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..style.display = 'none';
  web.document.body!.append(input);

  void finish(List<PickedFile> result, [Object? error]) {
    input.remove();
    if (completer.isCompleted) return;
    error == null ? completer.complete(result) : completer.completeError(error);
  }

  Future<void> onChange() async {
    final files = input.files;
    if (files == null || files.length == 0) return finish(const []);
    try {
      final picked = <PickedFile>[];
      for (var i = 0; i < files.length; i++) {
        final file = files.item(i)!;
        final buffer = await file.arrayBuffer().toDart;
        picked.add(PickedFile(
          name: file.name,
          contentType: file.type.isEmpty ? 'application/octet-stream' : file.type,
          bytes: buffer.toDart.asUint8List(),
        ));
      }
      finish(picked);
    } catch (e) {
      finish(const [], Exception('파일을 불러오지 못했어요.'));
    }
  }

  input.addEventListener(
    'change',
    ((web.Event _) {
      onChange();
    }).toJS,
  );
  input.addEventListener('cancel', ((web.Event _) => finish(const [])).toJS);
  input.click();
  return completer.future;
}

/// Hands [bytes] to the browser as a download named [fileName].
void saveFile(Uint8List bytes, String fileName, String contentType) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: contentType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Give the browser a moment to start the download before freeing the blob.
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
