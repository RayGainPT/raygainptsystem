import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/authorization_model.dart';
import '../models/guest_model.dart';

/// Fills an existing fillable PDF authorization template and flattens it.
/// Template must use exact form field names; no coordinate-based drawing.
class AuthorizationPdfService {
  AuthorizationPdfService();

  static const String _defaultTemplatePath =
      'assets/templates/authorization_template.pdf';

  static const int _maxGuests = AuthorizationModel.maxGuests;

  static final DateFormat _dateFormat = DateFormat('MMM dd, yyyy');

  /// Loads template from [templatePath] (or default), fills form fields from
  /// [data], flattens the form, and returns PDF bytes.
  ///
  /// [templatePath] defaults to [ _defaultTemplatePath ]. Pass a different path
  /// for template versioning (e.g. `assets/templates/authorization_template_v2.pdf`).
  ///
  /// Throws if guests length > 5.
  Future<Uint8List> generateAuthorizationPdf(
    AuthorizationModel data, {
    String? templatePath,
  }) async {
    if (data.guests.length > _maxGuests) {
      throw ArgumentError(
        'Authorization letter supports at most $_maxGuests guests; got ${data.guests.length}.',
      );
    }

    final path = templatePath?.trim().isNotEmpty == true
        ? templatePath!
        : _defaultTemplatePath;

    ByteData byteData;
    try {
      byteData = await rootBundle.load(path);
    } catch (e) {
      throw StateError(
        'Could not load template from "$path". '
        'Ensure the file exists under assets/templates/ (see assets/templates/README.txt).',
      );
    }
    final Uint8List bytes =
        byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);

    final PdfDocument document = PdfDocument(inputBytes: bytes);

    try {
      final PdfForm form = document.form;
      if (form.fields.count == 0) {
        document.dispose();
        throw StateError(
          'Template at "$path" has no form fields. Ensure it is a fillable PDF with the expected field names.',
        );
      }

      _setTextField(form, 'tower', data.tower);
      _setTextField(form, 'unit', data.unit);
      _setTextField(form, 'date_from', _dateFormat.format(data.fromDate));
      _setTextField(form, 'date_to', _dateFormat.format(data.toDate));
      _setTextField(form, 'unit_owner_name', data.unitOwnerName);
      if (data.signatureImageBytes != null && data.signatureImageBytes!.isNotEmpty) {
        _setTextField(form, 'owner_signature', '');
        _drawSignatureImage(document, form, data.signatureImageBytes!);
      } else {
        _setTextField(form, 'owner_signature', data.ownerSignature);
      }

      // "Given this ___ day of ______, 20__."
      final given = data.givenThisDayDate;
      _setTextField(form, 'given_day', given.day.toString());
      _setTextField(form, 'given_month', DateFormat('MMMM').format(given));
      _setTextField(form, 'given_year', DateFormat('yy').format(given));

      for (int i = 0; i < _maxGuests; i++) {
        final int oneBased = i + 1;
        final String nameKey = 'guest_${oneBased}_name';
        final String proofKey = 'guest_${oneBased}_proof';
        final String relationshipKey = 'guest_${oneBased}_relationship';

        if (i < data.guests.length) {
          final GuestModel guest = data.guests[i];
          _setTextField(form, nameKey, guest.name);
          _setTextField(form, proofKey, guest.proofOfId);
          _setTextField(form, relationshipKey, guest.relationship);
        } else {
          _setTextField(form, nameKey, '');
          _setTextField(form, proofKey, '');
          _setTextField(form, relationshipKey, '');
        }
      }

      form.flattenAllFields();

      return document.saveAsBytesSync();
    } finally {
      document.dispose();
    }
  }

  /// Finds a form field by name. Returns null if not found.
  PdfField? _findField(PdfForm form, String name) {
    for (int i = 0; i < form.fields.count; i++) {
      final PdfField field = form.fields[i];
      if (field.name == name) return field;
    }
    return null;
  }

  /// Draws the signature image on the page at the owner_signature field bounds.
  void _drawSignatureImage(PdfDocument document, PdfForm form, Uint8List imageBytes) {
    final PdfField? field = _findField(form, 'owner_signature');
    if (field == null || field.page == null) return;
    final ui.Rect bounds = field.bounds;
    if (bounds.width <= 0 || bounds.height <= 0) return;
    try {
      final PdfBitmap bitmap = PdfBitmap(imageBytes);
      field.page!.graphics.drawImage(bitmap, bounds);
    } catch (_) {
      // Image format not supported or invalid; skip drawing
    }
  }

  /// Finds a form field by name and sets its text if it is a text box.
  /// Does nothing if the field is missing (avoids crash).
  void _setTextField(PdfForm form, String name, String value) {
    for (int i = 0; i < form.fields.count; i++) {
      final PdfField field = form.fields[i];
      if (field.name == name) {
        if (field is PdfTextBoxField) {
          field.text = value;
        }
        return;
      }
    }
  }
}
