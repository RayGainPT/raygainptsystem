import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:printing/printing.dart';
import '../models/booking.dart';
import '../utils/pdf_generator.dart';

class BookingCard extends StatefulWidget {
  final DocumentSnapshot doc;
  const BookingCard({Key? key, required this.doc}) : super(key: key);

  @override
  State<BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<BookingCard> {
  Timer? _timer;
  Duration _timeLeft = Duration.zero;

  String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  void _updateTimeLeft() {
    final map =
        widget.doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    final expires = map['expiresAt'];
    if (expires == null) {
      setState(() => _timeLeft = Duration.zero);
      return;
    }
    DateTime exp;
    if (expires is Timestamp)
      exp = expires.toDate();
    else if (expires is DateTime)
      exp = expires;
    else {
      setState(() => _timeLeft = Duration.zero);
      return;
    }
    final now = DateTime.now();
    setState(() =>
        _timeLeft = exp.isAfter(now) ? exp.difference(now) : Duration.zero);
  }

  @override
  void initState() {
    super.initState();
    _updateTimeLeft();
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateTimeLeft());
  }

  @override
  void didUpdateWidget(covariant BookingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doc.id != widget.doc.id) _updateTimeLeft();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _pretty(Duration d) {
    if (d <= Duration.zero) return 'expired';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  Color _statusColor(String s) {
    final key = s.toLowerCase();
    if (key == 'verified') return Colors.green.shade600;
    if (key == 'rejected') return Colors.red.shade600;
    return Colors.orange.shade600;
  }

  void _openImage(BuildContext context, String? url) {
    if (url == null || url.isEmpty) {
      showDialog(
          context: context,
          builder: (_) =>
              const AlertDialog(content: Text('No Image Provided')));
      return;
    }

    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 5.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 800, maxWidth: 800),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const SizedBox(
                    height: 240,
                    child: Center(child: CircularProgressIndicator()));
              },
              errorBuilder: (context, error, stackTrace) => const SizedBox(
                  height: 240,
                  child: Center(
                      child: Icon(Icons.broken_image,
                          color: Colors.red, size: 48))),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAction(BuildContext context, String status) async {
    final controller = TextEditingController();
    final actionLabel = status == 'verified' ? 'Verify' : 'Reject';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$actionLabel booking', style: GoogleFonts.poppins()),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Optional: add a reason for this action',
              style:
                  GoogleFonts.poppins(fontSize: 13, color: Colors.grey[700])),
          const SizedBox(height: 8),
          TextField(
              controller: controller,
              decoration: InputDecoration(
                  border: OutlineInputBorder(), hintText: 'Reason (optional)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: GoogleFonts.poppins())),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(actionLabel, style: GoogleFonts.poppins())),
        ],
      ),
    );
    if (confirmed == true) {
      final prevMap =
          widget.doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
      final prevStatus = (prevMap['paymentStatus'] ?? 'pending') as String?;
      final prevReason = (prevMap['statusReason'] ?? '') as String?;
      try {
        await widget.doc.reference.update({
          'paymentStatus': status,
          'statusReason': controller.text.trim(),
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${actionLabel}d'),
          action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                try {
                  await widget.doc.reference.update({
                    'paymentStatus': prevStatus ?? 'pending',
                    'statusReason': prevReason ?? '',
                    'statusUpdatedAt': FieldValue.serverTimestamp(),
                  });
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Undo successful')));
                } catch (e) {
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Undo failed: $e')));
                }
              }),
        ));
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data =
        widget.doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    final guest = (data['guestName'] ?? 'Guest') as String;
    // Support both legacy single `idUrl` and new `idUrls` list
    final dynamic idUrlsRaw = data['idUrls'] ?? data['idUrl'];
    final List<String> idUrls = <String>[];
    if (idUrlsRaw is List) {
      for (final v in idUrlsRaw) if (v != null) idUrls.add(v.toString());
    } else if (idUrlsRaw != null) {
      idUrls.add(idUrlsRaw.toString());
    }
    final receiptUrl = data['receiptUrl'] as String?;
    final total = (data['totalPrice'] ?? 0).toString();
    final status = (data['paymentStatus'] ?? 'pending') as String;
    final reason = (data['statusReason'] ?? '') as String;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10))
            ],
            border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 520;

            Widget thumbnails = Row(children: [
              GestureDetector(
                onTap: () => _openImage(context, receiptUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 80,
                    height: 80,
                    color: Colors.grey.shade100,
                    child: (receiptUrl != null && receiptUrl.isNotEmpty)
                        ? Image.network(receiptUrl,
                            width: 80, height: 80, fit: BoxFit.cover)
                        : const Center(
                            child: Text('No Image Provided',
                                style: TextStyle(fontSize: 10))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // ID thumbnails: show first image and indicate multiple, or a small horizontal list
              if (idUrls.isEmpty)
                GestureDetector(
                  onTap: () => _openImage(context, null),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 80,
                      height: 80,
                      color: Colors.grey.shade100,
                      child: const Center(
                          child: Text('No Image Provided',
                              style: TextStyle(fontSize: 10))),
                    ),
                  ),
                )
              else if (idUrls.length == 1)
                GestureDetector(
                  onTap: () => _openImage(context, idUrls.first),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 80,
                      height: 80,
                      color: Colors.grey.shade100,
                      child: Image.network(idUrls.first,
                          width: 80, height: 80, fit: BoxFit.cover),
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: () => _openIdsGallery(
                      idUrls,
                      (data['guestNames'] is List)
                          ? List<String>.from(
                              data['guestNames'].map((e) => e.toString()))
                          : [guest]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 120,
                      height: 80,
                      color: Colors.grey.shade100,
                      child: Stack(children: [
                        Positioned.fill(
                            child: Image.network(idUrls.first,
                                width: 120, height: 80, fit: BoxFit.cover)),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(12)),
                            child: Text('+${idUrls.length - 1}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ),
                        )
                      ]),
                    ),
                  ),
                ),
            ]);

            Widget actionsColumn() {
              return Column(mainAxisSize: MainAxisSize.min, children: [
                if (status.toLowerCase() == 'verified') ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download_rounded),
                    label: Text('Download PDF',
                        style:
                            GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(140, 44)),
                    onPressed: () async {
                      try {
                        final map =
                            widget.doc.data() as Map<String, dynamic>? ??
                                <String, dynamic>{};
                        DateTime parseSafe(dynamic v, DateTime fallback) {
                          if (v == null) return fallback;
                          if (v is Timestamp) return v.toDate();
                          if (v is DateTime) return v;
                          if (v is String) {
                            try {
                              return DateTime.parse(v);
                            } catch (_) {
                              return fallback;
                            }
                          }
                          return fallback;
                        }

                        final created =
                            parseSafe(map['createdAt'], DateTime.now());
                        final checkIn = parseSafe(
                            map['checkInDate'] ??
                                map['checkIn'] ??
                                map['createdAt'],
                            created);
                        final checkOut = map['checkOutDate'] != null
                            ? parseSafe(map['checkOutDate'],
                                checkIn.add(const Duration(days: 1)))
                            : null;

                        final booking = Booking.fromMap({
                          ...map,
                          'checkIn': checkIn.toIso8601String(),
                          'checkOut': checkOut?.toIso8601String() ??
                              checkIn.toIso8601String()
                        }, widget.doc.id);

                        String? idType;
                        if (map['idType'] != null)
                          idType = map['idType'].toString();
                        else if (map['idDocumentType'] != null)
                          idType = map['idDocumentType'].toString();
                        else if (map['idName'] != null)
                          idType = map['idName'].toString();

                        final bytes = await generateAuthorizationPDF(booking,
                            idType: idType);
                        await Printing.sharePdf(
                            bytes: bytes,
                            filename: 'Authorization_${widget.doc.id}.pdf');
                      } catch (e) {
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Failed to generate PDF: $e')));
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.preview),
                    label: Text('Preview',
                        style:
                            GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                    onPressed: () async {
                      try {
                        final map =
                            widget.doc.data() as Map<String, dynamic>? ??
                                <String, dynamic>{};
                        DateTime parseSafe(dynamic v, DateTime fallback) {
                          if (v == null) return fallback;
                          if (v is Timestamp) return v.toDate();
                          if (v is DateTime) return v;
                          if (v is String) {
                            try {
                              return DateTime.parse(v);
                            } catch (_) {
                              return fallback;
                            }
                          }
                          return fallback;
                        }

                        final created =
                            parseSafe(map['createdAt'], DateTime.now());
                        final checkIn = parseSafe(
                            map['checkInDate'] ??
                                map['checkIn'] ??
                                map['createdAt'],
                            created);
                        final checkOut = map['checkOutDate'] != null
                            ? parseSafe(map['checkOutDate'],
                                checkIn.add(const Duration(days: 1)))
                            : null;

                        final booking = Booking.fromMap({
                          ...map,
                          'checkIn': checkIn.toIso8601String(),
                          'checkOut': checkOut?.toIso8601String() ??
                              checkIn.toIso8601String()
                        }, widget.doc.id);

                        String? idType;
                        if (map['idType'] != null)
                          idType = map['idType'].toString();
                        else if (map['idDocumentType'] != null)
                          idType = map['idDocumentType'].toString();
                        else if (map['idName'] != null)
                          idType = map['idName'].toString();

                        await showDialog<void>(
                          context: context,
                          builder: (ctx) => Dialog(
                            insetPadding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: isNarrow ? double.infinity : 600,
                              height: isNarrow ? 600 : 800,
                              child: PdfPreview(
                                allowPrinting: true,
                                allowSharing: true,
                                build: (format) async =>
                                    generateAuthorizationPDF(booking,
                                        idType: idType),
                              ),
                            ),
                          ),
                        );
                      } catch (e) {
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Failed to show preview: $e')));
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  InkWell(
                    onTap: () => _verifyAndNotify(),
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF2ECC71), Color(0xFF1FA055)]),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: const Offset(0, 3))
                        ],
                      ),
                      child: Text('Verify',
                          style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE63946),
                    shape: const StadiumBorder(),
                    minimumSize: const Size(110, 44),
                  ),
                  onPressed: () => _confirmAction(context, 'Rejected'),
                  child: Text('Reject',
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ]);
            }

            if (isNarrow) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      CircleAvatar(
                          radius: 28,
                          child: Text(_initials(guest),
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(guest,
                              style: GoogleFonts.inter(
                                  fontSize: 16, fontWeight: FontWeight.w700))),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 10),
                          decoration: BoxDecoration(
                              color: _statusColor(status),
                              borderRadius: BorderRadius.circular(12)),
                          child: Text(status.replaceAll('_', ' '),
                              style: GoogleFonts.poppins(
                                  color: Colors.white, fontSize: 12)))
                    ]),
                    const SizedBox(height: 10),
                    Text('Total Paid: ₱ $total',
                        style:
                            GoogleFonts.poppins(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.access_time,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text('Time Left: ${_pretty(_timeLeft)}',
                          style: GoogleFonts.poppins(
                              color: Colors.grey[600], fontSize: 12))
                    ]),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(reason,
                          style: GoogleFonts.poppins(
                              color: Colors.grey[600],
                              fontSize: 12,
                              fontStyle: FontStyle.italic))
                    ],
                    const SizedBox(height: 12),
                    thumbnails,
                    const SizedBox(height: 12),
                    actionsColumn(),
                  ]);
            }

            // Desktop / wide layout: keep original row layout
            return Row(children: [
              // Left: avatar
              CircleAvatar(
                  radius: 28,
                  child: Text(_initials(guest),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700))),
              const SizedBox(width: 12),

              // Center: details
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(guest,
                                style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700))),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 6, horizontal: 10),
                            decoration: BoxDecoration(
                                color: _statusColor(status),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: status.startsWith('pending')
                                    ? [
                                        BoxShadow(
                                            color: Colors.orange
                                                .withValues(alpha: 0.15),
                                            blurRadius: 8,
                                            spreadRadius: 1)
                                      ]
                                    : null),
                            child: Text(status.replaceAll('_', ' '),
                                style: GoogleFonts.poppins(
                                    color: Colors.white, fontSize: 12))),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        Text('Total Paid: ',
                            style:
                                GoogleFonts.poppins(color: Colors.grey[700])),
                        Text('₱ $total',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w800))
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.access_time,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text('Time Left: ${_pretty(_timeLeft)}',
                            style: GoogleFonts.poppins(
                                color: Colors.grey[600], fontSize: 12))
                      ]),
                      if (reason.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(reason,
                            style: GoogleFonts.poppins(
                                color: Colors.grey[600],
                                fontSize: 12,
                                fontStyle: FontStyle.italic))
                      ],
                    ]),
              ),

              const SizedBox(width: 12),
              // thumbnails + actions
              thumbnails,
              const SizedBox(width: 12),
              actionsColumn(),
            ]);
          }),
        ),
      ),
    );
  }

  void _openIdsGallery(List<String> urls, List<String> names) {
    if (urls.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 700,
          height: 700,
          child: Column(children: [
            Expanded(
              child: PageView.builder(
                itemCount: urls.length,
                itemBuilder: (context, index) {
                  final url = urls[index];
                  final name = (names.length > index) ? names[index] : '';
                  return Column(children: [
                    Expanded(
                      child: InteractiveViewer(
                        child: Image.network(url,
                            fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => Container(
                                color: Colors.grey.shade100,
                                child: const Center(
                                    child: Icon(Icons.broken_image)))),
                      ),
                    ),
                    Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                            name.isNotEmpty ? name : 'Guest ${index + 1}',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700))),
                  ]);
                },
              ),
            ),
            Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'))),
          ]),
        ),
      ),
    );
  }

  Future<void> _verifyAndNotify() async {
    final map =
        widget.doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    final guestPhone = (map['guestPhone'] ?? '') as String;
    final guestName = (map['guestName'] ?? 'Guest') as String;
    try {
      await widget.doc.reference.update({
        'paymentStatus': 'Verified',
        'statusUpdatedAt': FieldValue.serverTimestamp()
      });
      String _formatPhoneForWa(String raw) {
        var p = raw.trim();
        // keep only digits and optional leading +
        p = p.replaceAll(RegExp(r'[^0-9+]'), '');
        if (p.startsWith('+')) p = p.substring(1);
        if (p.startsWith('0')) p = '63' + p.substring(1);
        return p;
      }

      final message =
          'Hi $guestName! This is Euro Escape Staycation. Your payment has been VERIFIED. 🛡️ Your booking is now confirmed! We will send the check-in guides shortly.';
      final encoded = Uri.encodeComponent(message);
      final formatted = _formatPhoneForWa(guestPhone);
      if (formatted.isNotEmpty) {
        final waUrl = 'https://wa.me/$formatted?text=$encoded';
        await launchUrlString(waUrl);
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Guest phone number not available')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}
