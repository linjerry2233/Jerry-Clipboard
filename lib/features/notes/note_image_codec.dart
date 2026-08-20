import 'dart:convert';
import 'dart:typed_data';

String noteImageMimeType(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    _ => 'image/png',
  };
}

String buildNoteImageMarkdown(String fileName, List<int> bytes) {
  final mime = noteImageMimeType(fileName);
  return '\n![$fileName](data:$mime;base64,${base64Encode(bytes)})\n';
}

Uint8List? decodeNoteImageUri(Uri uri) {
  final source = uri.toString();
  if (!source.startsWith('data:image/') || !source.contains(',')) return null;
  try {
    return base64Decode(source.substring(source.indexOf(',') + 1));
  } catch (_) {
    return null;
  }
}
