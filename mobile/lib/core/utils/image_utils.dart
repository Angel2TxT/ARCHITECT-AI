import 'dart:convert';
import 'dart:typed_data';

Uint8List decodeBase64Image(String raw) {
  final value = raw.contains(',') ? raw.split(',').last : raw;
  return base64Decode(value);
}
