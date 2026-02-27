import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/booking.dart';

class PdfServiceSyncfusion {
  const PdfServiceSyncfusion();

  /// Generate a filled SMDC Greenmist form based on the asset
  /// `assets/pmo_form.pdf` and the provided [booking]. Returns the
  /// resulting PDF bytes as [Uint8List].
  Future<Uint8List> generateFilledLetter(Booking booking,
      {String? templateUrl}) async {
    // Load the existing PDF form from provided templateUrl or fallback to assets
    Uint8List bytes;
    if (templateUrl != null && templateUrl.isNotEmpty) {
      try {
        final httpClient = HttpClient();
        final request = await httpClient.getUrl(Uri.parse(templateUrl));
        final response = await request.close();
        if (response.statusCode == 200) {
          bytes = await consolidateHttpClientResponseBytes(response);
        } else {
          // fallback to bundled asset
          final data = await rootBundle.load('assets/pmo_form.pdf');
          bytes = data.buffer.asUint8List();
        }
      } catch (_) {
        final data = await rootBundle.load('assets/pmo_form.pdf');
        bytes = data.buffer.asUint8List();
      }
    } else {
      final data = await rootBundle.load('assets/pmo_form.pdf');
      bytes = data.buffer.asUint8List();
    }

    // Open the document
    final PdfDocument document = PdfDocument(inputBytes: bytes);

    // We'll draw onto the first page
    final PdfPage page = document.pages[0];
    final PdfGraphics graphics = page.graphics;

    // Prepare drawing font
    final PdfFont font = PdfStandardFont(PdfFontFamily.helvetica, 10);
    final PdfFont bold =
        PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);

    // Format dates
    final String startLabel = _formatDate(booking.checkIn);
    final String endLabel = _formatDate(booking.checkOut);

    // Draw check-in / check-out at specified coordinates (page 1 coords)
    graphics.drawString(startLabel, font,
        brush: PdfBrushes.black, bounds: ui.Rect.fromLTWH(375, 680, 120, 20));
    graphics.drawString(endLabel, font,
        brush: PdfBrushes.black, bounds: ui.Rect.fromLTWH(470, 680, 120, 20));

    // Guest table: start y=600, step 25 per guest. Draw Name | ID Type | Relationship
    double y = 600.0;
    const double xName =
        80.0; // approximate column positions tuned for SMDC form
    const double xIdType = 320.0;
    const double xRelation = 440.0;
    final guests = await _extractGuestsFromBooking(booking);
    for (final g in guests) {
      final String name = g['name'] ?? '';
      final String idType = g['idType'] ?? '';
      final String relation = g['relation'] ?? '';
      graphics.drawString(name, font,
          brush: PdfBrushes.black, bounds: ui.Rect.fromLTWH(xName, y, 220, 18));
      graphics.drawString(idType, font,
          brush: PdfBrushes.black,
          bounds: ui.Rect.fromLTWH(xIdType, y, 110, 18));
      graphics.drawString(relation, font,
          brush: PdfBrushes.black,
          bounds: ui.Rect.fromLTWH(xRelation, y, 120, 18));
      y -= 25; // move down
    }

    // Property info: use unit from property if available, fallback to hardcoded
    String unitLabel = 'Tower 14 Unit 552';
    try {
      if (booking.propertyId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('properties')
            .doc(booking.propertyId)
            .get();
        if (doc.exists) {
          final data = doc.data();
          if (data != null && data['unitDetails'] != null) {
            unitLabel = data['unitDetails'].toString();
          }
        }
      }
    } catch (_) {}
    // Draw unit info at a reasonable place on the form (adjust coords if needed)
    graphics.drawString(unitLabel, bold,
        brush: PdfBrushes.black, bounds: ui.Rect.fromLTWH(120, 720, 300, 18));

    // Signature: attempt to fetch owner signature if available via property.ownerId -> users.ownerId.signatureUrl
    try {
      if (booking.propertyId.isNotEmpty) {
        final prop = await FirebaseFirestore.instance
            .collection('properties')
            .doc(booking.propertyId)
            .get();
        if (prop.exists) {
          final pdata = prop.data();
          final ownerId = pdata?['ownerId'];
          if (ownerId is String && ownerId.isNotEmpty) {
            final ownerDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(ownerId)
                .get();
            if (ownerDoc.exists) {
              final od = ownerDoc.data();
              final sigUrl = od?['signatureUrl'] as String?;
              if (sigUrl != null && sigUrl.isNotEmpty) {
                // fetch signature bytes over network
                try {
                  final httpClient2 = HttpClient();
                  final req2 = await httpClient2.getUrl(Uri.parse(sigUrl));
                  final resp2 = await req2.close();
                  if (resp2.statusCode == 200) {
                    final bytesList =
                        await consolidateHttpClientResponseBytes(resp2);
                    final PdfBitmap signature = PdfBitmap(bytesList);
                    // Draw the signature at approximate coordinates for "Signature of Unit Owner"
                    final double sigX = 380;
                    final double sigY = 720;
                    graphics.drawImage(
                        signature, ui.Rect.fromLTWH(sigX, sigY, 120, 40));
                  }
                } catch (_) {}
              }
            }
          }
        }
      }
    } catch (_) {}

    // Save and return modified PDF bytes
    final List<int> result = document.saveSync();
    document.dispose();
    return Uint8List.fromList(result);
  }

  String _formatDate(DateTime d) {
    try {
      return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return '';
    }
  }

  Future<List<Map<String, String>>> _extractGuestsFromBooking(
      Booking booking) async {
    // Booking model in this project stores a single guestName and paxCount.
    // If the project stores more detailed guest arrays in Firestore, fetch them.
    // For now, synthesize guest rows from booking.guestName and paxCount.
    final List<Map<String, String>> rows = [];
    rows.add({'name': booking.guestName, 'idType': 'ID', 'relation': 'Guest'});
    return rows;
  }
}
