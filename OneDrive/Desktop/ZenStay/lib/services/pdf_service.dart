import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Simple position container used by templates. Coordinates are PDF points
/// measured from the top-left of the page. `page` is 1-based.
class TemplatePosition {
  final double x;
  final double y;
  final int page;
  final double? width;
  final double? height;

  const TemplatePosition(this.x, this.y,
      {this.page = 1, this.width, this.height});
}

/// Defines a property PDF template: background (base) PDF/image URL and a map
/// of named positions where data should be rendered.
class PropertyTemplate {
  /// URL to an image/pdf used as the page background for page 1.
  final String backgroundUrl;

  /// Named positions used by the renderer: e.g. 'from','to','guestTable','signature'.
  final Map<String, TemplatePosition> positions;

  /// Page size to render to (defaults to A4). Use `PdfPageFormat.a4` or custom.
  final PdfPageFormat pageFormat;

  const PropertyTemplate({
    required this.backgroundUrl,
    required this.positions,
    this.pageFormat = PdfPageFormat.a4,
  });
}

class PdfService {
  const PdfService();

  /// Generate an authorization PDF using the provided [template].
  ///
  /// - [startDate]/[endDate] are the booking range (inclusive start, inclusive end for nights calculation).
  /// - [guests] is a list of maps with keys `name` and `idType` (both strings).
  /// - [ownerSignaturePng] is the PNG bytes of the owner's signature (optional).
  Future<Uint8List> generateAuthorizationPdf({
    required PropertyTemplate template,
    required DateTime startDate,
    required DateTime endDate,
    required List<Map<String, String>> guests,
    Uint8List? ownerSignaturePng,
  }) async {
    final doc = pw.Document();

    // Fetch background image bytes (supports HTTP(S) urls)
    final bgBytes = await _fetchBytes(template.backgroundUrl);
    final bgImage = pw.MemoryImage(bgBytes);

    // Pre-format dates
    final df = DateFormat('MMM dd, yyyy');
    final fromLabel = df.format(startDate);
    final toLabel = df.format(endDate);

    // Compute nights (end exclusive for nights: e.g. Feb24 - Feb26 = 2 nights)
    final nights = endDate.difference(startDate).inDays;

    // Build a single page with the background and overlays. The template positions
    // are interpreted in PDF points (1/72 inch). The caller should ensure
    // coordinates match the [pageFormat] used.
    doc.addPage(
      pw.Page(
        pageFormat: template.pageFormat,
        build: (context) {
          return pw.Stack(children: [
            // Background (fills the page)
            pw.Positioned.fill(
              child: pw.Image(bgImage, fit: pw.BoxFit.cover),
            ),

            // From (start date)
            if (template.positions.containsKey('from'))
              _positionedText(template.positions['from']!, fromLabel,
                  bold: false),

            // To (end date)
            if (template.positions.containsKey('to'))
              _positionedText(template.positions['to']!, toLabel, bold: false),

            // Nights badge (if requested position exists)
            if (template.positions.containsKey('nights'))
              _positionedText(template.positions['nights']!,
                  '$nights Night${nights == 1 ? '' : 's'}',
                  bold: true),

            // Guest table
            if (template.positions.containsKey('guestTable'))
              _positionedGuestTable(template.positions['guestTable']!, guests),

            // Signature stamp
            if (ownerSignaturePng != null &&
                template.positions.containsKey('signature'))
              _positionedImage(
                  template.positions['signature']!, ownerSignaturePng),
          ]);
        },
      ),
    );

    return doc.save();
  }

  Future<Uint8List> _fetchBytes(String url) async {
    final uri = Uri.parse(url);
    final res = await http.get(uri);
    if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    throw Exception('Failed to fetch $url (status ${res.statusCode})');
  }

  pw.Widget _positionedText(TemplatePosition pos, String text,
      {bool bold = false, double fontSize = 12}) {
    return pw.Positioned(
      left: pos.x,
      top: pos.y,
      child: pw.Container(
        width: pos.width ?? 200,
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: fontSize,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ),
    );
  }

  pw.Widget _positionedImage(TemplatePosition pos, Uint8List bytes,
      {double maxWidth = 140}) {
    final img = pw.MemoryImage(bytes);
    return pw.Positioned(
      left: pos.x,
      top: pos.y,
      child: pw.Container(
        width: pos.width ?? maxWidth,
        height: pos.height ?? (pos.width != null ? pos.width! * 0.4 : 40),
        child: pw.Image(img, fit: pw.BoxFit.contain),
      ),
    );
  }

  pw.Widget _positionedGuestTable(
      TemplatePosition pos, List<Map<String, String>> guests) {
    // Build a simple two-column table: Name | ID Type
    final headers = ['Name of Guest(s)', 'ID Type'];
    final rows =
        guests.map((g) => [g['name'] ?? '', g['idType'] ?? '']).toList();
    return pw.Positioned(
      left: pos.x,
      top: pos.y,
      child: pw.Container(
        width: pos.width ?? 300,
        child: pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          cellAlignment: pw.Alignment.centerLeft,
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: pw.TextStyle(fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.white),
          columnWidths: {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2)},
        ),
      ),
    );
  }
}
