// ignore_for_file: avoid_print

import 'dart:io';
import 'package:image/image.dart' as img;

void main() async {
  final sourcePath = 'assets/icons/app_icon.png';
  final icoPaths = [
    'assets/icons/app_icon.ico',
    'windows/runner/resources/app_icon.ico',
  ];

  final sourceFile = File(sourcePath);
  if (!await sourceFile.exists()) {
    print('Error: $sourcePath not found');
    return;
  }

  final sourceBytes = await sourceFile.readAsBytes();
  final sourceImage = img.decodeImage(sourceBytes);

  if (sourceImage == null) {
    print('Error: Failed to decode $sourcePath');
    return;
  }

  final resizedImage = img.copyResize(sourceImage, width: 256, height: 256);

  final icoImage = img.encodeIco(resizedImage);

  for (final icoPath in icoPaths) {
    final parent = File(icoPath).parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await File(icoPath).writeAsBytes(icoImage);
    print('Icon converted successfully: $icoPath');
  }
}
