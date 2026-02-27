import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../models/booking.dart';

/// Generate an authorization PDF using the provided [Booking].
/// Returns a Uint8List with the PDF bytes.
Future<Uint8List> generateAuthorizationPDF(Booking booking,
    {String? idType}) async {
  final pdf = pw.Document();

  final dateFmt = DateFormat('MMMM dd, yyyy');

  final checkIn = booking.checkIn;
  final checkOut = booking.checkOut;

  final period = '${dateFmt.format(checkIn)} - ${dateFmt.format(checkOut)}';

  final names = <String>[booking.guestName];
  if (booking.paxCount > 1) {
    names.add('and ${booking.paxCount - 1} additional guest(s)');
  }

  final idText =
      (idType != null && idType.isNotEmpty) ? idType : 'Valid ID is attached.';

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) {
        return pw.Padding(
          padding: const pw.EdgeInsets.all(32),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('TREES RESIDENCES',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('Authorization Letter',
                  style: pw.TextStyle(fontSize: 14)),
              pw.Divider(),
              pw.SizedBox(height: 12),
              pw.Text('Unit Location:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('Tower 14 Unit 552'),
              pw.SizedBox(height: 12),
              pw.Text('Name of Guest:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(names.join(', ')),
              pw.SizedBox(height: 12),
              pw.Text('Period:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(period),
              pw.SizedBox(height: 12),
              pw.Text('Proof of Identification:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(idText),
              pw.Spacer(),
              pw.Text(
                  'I hereby authorize the property manager to process the reservation and facilitate access as required.',
                  style: pw.TextStyle(fontSize: 12)),
              pw.SizedBox(height: 40),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Guest signature',
                              style: pw.TextStyle(fontSize: 12)),
                          pw.SizedBox(height: 40),
                          pw.Container(
                              width: 220, height: 1, color: PdfColors.grey300),
                        ]),
                    pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Date', style: pw.TextStyle(fontSize: 12)),
                          pw.SizedBox(height: 40),
                          pw.Container(
                              width: 120, height: 1, color: PdfColors.grey300),
                        ]),
                  ])
            ],
          ),
        );
      },
    ),
  );

  return pdf.save();
}

/// Convenience function: generate and trigger download/share of the PDF (uses printing)
Future<void> generateAndShareAuthorizationPDF(Booking booking,
    {String? filename}) async {
  final bytes = await generateAuthorizationPDF(booking);
  final name = filename ?? 'Authorization_${booking.bookingId}.pdf';
  await Printing.sharePdf(bytes: bytes, filename: name);
}
