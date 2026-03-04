import 'dart:typed_data';

import 'guest_model.dart';

/// Structured input for the condominium authorization letter PDF.
class AuthorizationModel {
  final String tower;
  final String unit;
  final DateTime fromDate;
  final DateTime toDate;
  final String unitOwnerName;
  /// Date for "Given this ___ day of ______, 20__."
  final DateTime givenThisDayDate;
  /// Optional signature image (PNG/JPG bytes) to place in owner_signature field.
  /// If null, [ownerSignature] text is used if provided.
  final Uint8List? signatureImageBytes;
  /// Fallback text for owner signature when no image is provided.
  final String ownerSignature;
  final List<GuestModel> guests;

  const AuthorizationModel({
    required this.tower,
    required this.unit,
    required this.fromDate,
    required this.toDate,
    required this.unitOwnerName,
    required this.givenThisDayDate,
    this.signatureImageBytes,
    this.ownerSignature = '',
    required this.guests,
  });

  /// Max guest rows supported by the template.
  static const int maxGuests = 5;
}
