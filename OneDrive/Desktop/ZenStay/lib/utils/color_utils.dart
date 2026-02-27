import 'package:flutter/material.dart';

class ColorUtils {
  /// Converts a Hex String (e.g., "#673AB7" or "673AB7") to a Flutter Color object.
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  /// Converts a Flutter Color object back to a Hex String for Firestore storage.
  static String toHex(Color color) {
    // Use toARGB32() to follow newer Color API and avoid deprecated .value usage
    final int argb = color.toARGB32();
    return '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }
}
