import 'package:cloud_firestore/cloud_firestore.dart';

class Booking {
  final String bookingId;
  final String propertyId;
  final String guestName;
  final String guestPhone;
  final int paxCount;
  final DateTime checkIn;
  final DateTime checkOut;
  final String paymentStatus;
  final String paymentReceiptUrl;
  final String guestIdUrl;
  final num totalPrice;
  final String securityDepositStatus;
  final DateTime createdAt;
  final DateTime expiresAt;

  Booking({
    required this.bookingId,
    required this.propertyId,
    required this.guestName,
    required this.guestPhone,
    required this.paxCount,
    required this.checkIn,
    required this.checkOut,
    required this.paymentStatus,
    required this.paymentReceiptUrl,
    required this.guestIdUrl,
    required this.totalPrice,
    required this.securityDepositStatus,
    required this.createdAt,
    required this.expiresAt,
  });

  factory Booking.fromMap(Map<String, dynamic> data, String id) {
    Timestamp parseTs(dynamic v) =>
        v is Timestamp ? v : Timestamp.fromDate(DateTime.parse(v));

    return Booking(
      bookingId: id,
      propertyId: data['propertyId'] ?? '',
      guestName: data['guestName'] ?? '',
      guestPhone: data['guestPhone'] ?? '',
      paxCount: (data['paxCount'] ?? 0) as int,
      checkIn: (parseTs(data['checkIn'])).toDate(),
      checkOut: (parseTs(data['checkOut'])).toDate(),
      paymentStatus: data['paymentStatus'] ?? '',
      paymentReceiptUrl: data['paymentReceiptUrl'] ?? '',
      guestIdUrl: data['guestIdUrl'] ?? '',
      totalPrice: data['totalPrice'] ?? 0,
      securityDepositStatus: data['securityDepositStatus'] ?? '',
      createdAt: (parseTs(data['createdAt'])).toDate(),
      expiresAt: (parseTs(data['expiresAt'])).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'propertyId': propertyId,
      'guestName': guestName,
      'guestPhone': guestPhone,
      'paxCount': paxCount,
      'checkIn': Timestamp.fromDate(checkIn),
      'checkOut': Timestamp.fromDate(checkOut),
      'paymentStatus': paymentStatus,
      'paymentReceiptUrl': paymentReceiptUrl,
      'guestIdUrl': guestIdUrl,
      'totalPrice': totalPrice,
      'securityDepositStatus': securityDepositStatus,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
    };
  }
}
