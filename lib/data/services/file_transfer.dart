import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Document types a 댓글 may carry — keep in step with the server's allow-list
/// (server/src/routes/memos.js).
const commentFileExtensions = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'hwp', 'hwpx', 'txt', 'csv', 'zip'];

class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Opens the browser's file chooser for one document. Resolves to null if
/// the user cancels.
Future<PickedFile?> pickDocument() {
  final completer = Completer<PickedFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = commentFileExtensions.map((e) => '.$e').join(',')
    ..style.display = 'none';
  web.document.body!.append(input);

  void finish(PickedFile? result, [Object? error]) {
    input.remove();
    if (completer.isCompleted) return;
    error == null ? completer.complete(result) : completer.completeError(error);
  }

  Future<void> onChange() async {
    final file = input.files?.item(0);
    if (file == null) return finish(null);
    try {
      final buffer = await file.arrayBuffer().toDart;
      finish(PickedFile(name: file.name, bytes: buffer.toDart.asUint8List()));
    } catch (e) {
      finish(null, Exception('파일을 불러오지 못했어요.'));
    }
  }

  input.addEventListener('change', ((web.Event _) {
    onChange();
  }).toJS);
  input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);
  input.click();
  return completer.future;
}

/// Hands [bytes] to the browser as a download named [fileName].
void saveFile(String fileName, Uint8List bytes) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/octet-stream'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
