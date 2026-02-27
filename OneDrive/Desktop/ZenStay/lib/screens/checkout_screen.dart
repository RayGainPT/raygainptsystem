import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'success_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final double total;
  final List<dynamic> paymentMethods;
  final String slug;
  final DateTime checkInDate;
  final String selectedDuration;
  final int totalPax;
  final List<DateTime>? stayDates;
  final double baseStayPrice;
  final double totalExtraPaxFee;
  final double securityDeposit;
  final List<String>? guestIdUrls;

  const CheckoutScreen(
      {Key? key,
      required this.total,
      required this.paymentMethods,
      required this.slug,
      required this.checkInDate,
      required this.selectedDuration,
      required this.totalPax,
      required this.baseStayPrice,
      required this.totalExtraPaxFee,
      required this.securityDeposit,
      this.stayDates,
      this.guestIdUrls})
      : super(key: key);

  @override
  _CheckoutScreenState createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late List<TextEditingController> guestNameControllers;
  late List<PlatformFile?> guestIdFiles;
  PlatformFile? receiptFile;
  bool isSubmitting = false;
  Map<String, dynamic>? propertyData;

  Future<void> _fetchPropertyData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.slug)
          .get();
      if (doc.exists) {
        final d = doc.data();
        if (d is Map<String, dynamic>) {
          setState(() => propertyData = d);
        } else {
          setState(() => propertyData = <String, dynamic>{});
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    guestNameControllers =
        List.generate(widget.totalPax, (_) => TextEditingController());
    guestIdFiles = List<PlatformFile?>.filled(widget.totalPax, null);
    _fetchPropertyData();
  }

  @override
  void dispose() {
    for (final c in guestNameControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickGuestId(int index) async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (res != null && res.files.isNotEmpty) {
      setState(() => guestIdFiles[index] = res.files.first);
    }
  }

  Future<void> _pickReceipt() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (res != null && res.files.isNotEmpty) {
      setState(() => receiptFile = res.files.first);
    }
  }

  bool get _canSubmit {
    // all guest names present
    final allNames =
        guestNameControllers.every((c) => c.text.trim().isNotEmpty);
    // all IDs uploaded
    final allIds = guestIdFiles.every((f) => f != null);
    // receipt uploaded
    final hasReceipt = receiptFile != null;
    return allNames && allIds && hasReceipt && !isSubmitting;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => isSubmitting = true);
    final scaffold = ScaffoldMessenger.of(context);
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Upload guest IDs
      final List<String> idUrls = [];
      for (var i = 0; i < guestIdFiles.length; i++) {
        final pf = guestIdFiles[i]!;
        if (pf.bytes == null) throw Exception('Missing file bytes');
        final ref = FirebaseStorage.instance
            .ref()
            .child('bookings')
            .child(widget.slug)
            .child('ID_${timestamp}_$i');
        final TaskSnapshot task = await ref.putData(pf.bytes!);
        final url = await task.ref.getDownloadURL();
        idUrls.add(url);
      }

      // Upload receipt
      final refReceipt = FirebaseStorage.instance
          .ref()
          .child('bookings')
          .child(widget.slug)
          .child('RECEIPT_${timestamp}');
      final TaskSnapshot receiptTask =
          await refReceipt.putData(receiptFile!.bytes!);
      final receiptUrl = await receiptTask.ref.getDownloadURL();

      // Compose guest names
      final List<String> guestNames =
          guestNameControllers.map((c) => c.text.trim()).toList();

      // Compute checkOut
      int _hoursFromDuration(String s) {
        try {
          return int.parse(s.replaceAll(RegExp(r'[^0-9]'), ''));
        } catch (_) {
          return 8;
        }
      }

      final DateTime checkIn = widget.checkInDate;
      final DateTime checkOut =
          widget.stayDates != null && widget.stayDates!.isNotEmpty
              ? widget.stayDates!.last.add(const Duration(days: 1))
              : checkIn.add(
                  Duration(hours: _hoursFromDuration(widget.selectedDuration)));

      // Persist booking
      await FirebaseFirestore.instance.collection('bookings').add({
        'propertySlug': widget.slug,
        'guestNames': guestNames,
        'totalPrice': widget.total,
        'idUrls': idUrls,
        'receiptUrl': receiptUrl,
        'paymentStatus': 'pending_verification',
        'createdAt': FieldValue.serverTimestamp(),
        'checkInDate': Timestamp.fromDate(checkIn),
        'checkOutDate': Timestamp.fromDate(checkOut),
        'stayDates': widget.stayDates != null
            ? widget.stayDates!.map((d) => Timestamp.fromDate(d)).toList()
            : null,
        'selectedDuration': widget.selectedDuration,
        'totalPax': widget.totalPax,
        'baseStayPrice': widget.baseStayPrice,
        'extraPaxFeeTotal': widget.totalExtraPaxFee,
        'securityDeposit': widget.securityDeposit,
      });

      setState(() => isSubmitting = false);
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SuccessScreen()));
    } catch (e) {
      setState(() => isSubmitting = false);
      scaffold.showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    }
  }

  // booking summary card removed (unused) to reduce analyzer warnings

  Widget _accountRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(child: Text('$label: $value')),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')));
            },
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // resolve property payment fields
    String? qrUrl = propertyData?['qrImageUrl'] ?? propertyData?['qrCodeUrl'];
    final String? gcashNumber =
        (propertyData?['gcashNumber'] ?? propertyData?['gcash'])?.toString();
    final String? mayaNumber =
        (propertyData?['mayaNumber'] ?? propertyData?['maya'])?.toString();
    final String? bankDetails =
        (propertyData?['bankDetails'] ?? propertyData?['bank'])?.toString();
    if (qrUrl == null) {
      for (final pm in widget.paymentMethods) {
        if (pm is Map) {
          qrUrl = qrUrl ?? (pm['qrUrl']?.toString() ?? pm['qr']?.toString());
        }
      }
    }

    final primaryColor = Theme.of(context).colorScheme.primary;
    final double grandTotal = widget.total;

    final photosRaw = propertyData?['propertyPhotos'];
    final List<String> photos = (photosRaw is List)
        ? photosRaw
            .map((e) => e?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>[];

    Widget orderSummaryCard({required bool compact}) {
      return Card(
        elevation: 10,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: photos.isNotEmpty
                        ? Image.network(photos.first,
                            width: 72, height: 72, fit: BoxFit.cover)
                        : Container(
                            width: 72,
                            height: 72,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.photo)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(propertyData?['title'] ?? widget.slug,
                          style: TextStyle(fontWeight: FontWeight.w700)))
                ]),
                const SizedBox(height: 12),
                Text('Price details',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                // explicit line items using passed values
                const SizedBox(height: 6),
                Builder(builder: (_) {
                  final int nights =
                      (widget.stayDates != null && widget.stayDates!.isNotEmpty)
                          ? widget.stayDates!.length
                          : 1;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                  'Stay ($nights Night${nights > 1 ? 's' : ''})'),
                              Text(
                                  '₱${widget.baseStayPrice.toStringAsFixed(2)}')
                            ]),
                        const SizedBox(height: 6),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Extra Guest Fee'),
                              Text(
                                  '₱${widget.totalExtraPaxFee.toStringAsFixed(2)}')
                            ]),
                        const SizedBox(height: 6),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Refundable Deposit'),
                              Text(
                                  '₱${widget.securityDeposit.toStringAsFixed(2)}')
                            ]),
                        const SizedBox(height: 12),
                        const Divider(height: 1, thickness: 1),
                        const SizedBox(height: 12),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Grand Total (PHP)',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                              Text('₱${grandTotal.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900))
                            ])
                      ]);
                }),
              ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
          title: Text('Confirm and pay',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700))),
      body: LayoutBuilder(builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 800;

        // Build common widgets
        final yourTripSection = Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your trip', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('Dates')),
                Text(widget.stayDates != null && widget.stayDates!.isNotEmpty
                    ? '${DateFormat('MMM dd').format(widget.stayDates!.first)} - ${DateFormat('MMM dd, yyyy').format(widget.stayDates!.last)}'
                    : DateFormat('MMM dd, yyyy').format(widget.checkInDate))
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: Text('Guests')),
                Text('${widget.totalPax}')
              ])
            ]),
          ),
        );

        final idsSection = Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Required for your trip',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Required by SMDC Greenmist PMO',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              const SizedBox(height: 12),
              ListView.builder(
                itemCount: widget.totalPax,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, i) {
                  final ctrl = guestNameControllers[i];
                  final file = guestIdFiles[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Expanded(
                        child: TextField(
                          controller: ctrl,
                          decoration: InputDecoration(
                            labelText: 'Guest ${i + 1} Full Name *',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints:
                            const BoxConstraints(minWidth: 72, maxWidth: 140),
                        child: OutlinedButton.icon(
                          onPressed: () => _pickGuestId(i),
                          icon: file != null
                              ? const Icon(Icons.check_circle, size: 16)
                              : const Icon(Icons.badge, size: 16),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(file != null ? 'Replace' : 'Attach ID',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(72, 40),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                          ),
                        ),
                      ),
                    ]),
                  );
                },
              )
            ]),
          ),
        );

        final paymentSection = Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Pay with', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (qrUrl != null && qrUrl.isNotEmpty)
                Center(
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(qrUrl,
                            width: 180, height: 180, fit: BoxFit.cover))),
              const SizedBox(height: 12),
              if (gcashNumber != null && gcashNumber.isNotEmpty)
                _accountRow('GCash', gcashNumber),
              if (mayaNumber != null && mayaNumber.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: _accountRow('Maya', mayaNumber)),
              if (bankDetails != null && bankDetails.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: _accountRow('Bank', bankDetails)),
              const SizedBox(height: 12),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 250),
                  child: ElevatedButton.icon(
                    onPressed: _pickReceipt,
                    icon: const Icon(Icons.upload_file, color: Colors.white),
                    label: Text('Attach Proof of Payment',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(250, 48),
                      textStyle: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                  child: Text('Confirm & Pay',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              )
            ]),
          ),
        );

        if (isDesktop) {
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 6,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Confirm and pay',
                            style: GoogleFonts.poppins(
                                fontSize: 28, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 18),
                        yourTripSection,
                        const SizedBox(height: 12),
                        idsSection,
                        const SizedBox(height: 12),
                        paymentSection,
                      ]),
                ),
                const SizedBox(width: 20),
                Expanded(
                    flex: 4,
                    child: Column(children: [
                      // sticky-like summary - keep it visible with spacing
                      SizedBox(height: 40),
                      orderSummaryCard(compact: false),
                    ])),
              ]),
            ),
          );
        }

        // Mobile layout: summary first
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  orderSummaryCard(compact: true),
                  const SizedBox(height: 12),
                  yourTripSection,
                  const SizedBox(height: 12),
                  idsSection,
                  const SizedBox(height: 12),
                  paymentSection,
                ]),
          ),
        );
      }),
    );
  }
}
