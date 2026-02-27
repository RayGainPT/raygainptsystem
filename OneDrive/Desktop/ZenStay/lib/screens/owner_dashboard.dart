import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../utils/color_utils.dart';

class OwnerDashboard extends StatefulWidget {
  final String? slug;
  const OwnerDashboard({Key? key, this.slug}) : super(key: key);

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 3;

  Color primaryColor = Colors.blue;
  Color secondaryColor = Colors.teal;
  bool isSavingTheme = false;
  bool isSavingRates = false;

  final TextEditingController slugController = TextEditingController();
  final TextEditingController extraPaxCtrl = TextEditingController();
  final TextEditingController maxBaseGuestsCtrl = TextEditingController();
  final TextEditingController extraPaxFeeCtrl = TextEditingController();
  final Map<String, TextEditingController> weekdayControllers = {};
  final Map<String, TextEditingController> weekendControllers = {};
  final TextEditingController weekdayNewLabelCtrl = TextEditingController();
  final TextEditingController weekdayNewRateCtrl = TextEditingController();
  final TextEditingController weekendNewLabelCtrl = TextEditingController();
  final TextEditingController weekendNewRateCtrl = TextEditingController();
  String? editingWeekdayKey;
  String? editingWeekendKey;
  final TextEditingController securityDepositCtrl = TextEditingController();
  final TextEditingController holidayNameCtrl = TextEditingController();
  final TextEditingController holidayDateCtrl = TextEditingController();
  final TextEditingController holiday8Ctrl = TextEditingController();
  final TextEditingController holiday10Ctrl = TextEditingController();
  final TextEditingController holiday12Ctrl = TextEditingController();
  final TextEditingController holiday22Ctrl = TextEditingController();
  final TextEditingController gcashCtrl = TextEditingController();
  final TextEditingController mayaCtrl = TextEditingController();
  final TextEditingController bankDetailsCtrl = TextEditingController();
  // Pricing & add-ons controllers
  final TextEditingController towelCtrl = TextEditingController();
  final TextEditingController cleaningCtrl = TextEditingController();
  final TextEditingController extraTableCtrl = TextEditingController();

  // Standard rate controllers (weekday)
  final TextEditingController weekday8Ctrl = TextEditingController();
  final TextEditingController weekday12Ctrl = TextEditingController();
  final TextEditingController weekday22Ctrl = TextEditingController();
  // Standard rate controllers (weekend)
  final TextEditingController weekend8Ctrl = TextEditingController();
  final TextEditingController weekend12Ctrl = TextEditingController();
  final TextEditingController weekend22Ctrl = TextEditingController();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> ownedProperties = [];
  String? currentPropertyId;
  bool _fetchCompleted = false;
  // staged holidays map: dateString -> { 'name': ..., '8h':..., '12h':..., '22h':... }
  final Map<String, Map<String, dynamic>> stagedHolidayRates = {};
  String? editingHolidayKey;

  @override
  void initState() {
    super.initState();
    securityDepositCtrl.text = '0';
    if (widget.slug != null) slugController.text = widget.slug!;
    _fetchOwnedProperties();
  }

  /// Fetches properties for the current user and locks the first as selected.
  /// Firestore field used: ownerId (matches property model and pdf_service).
  Future<void> _fetchOwnedProperties() async {
    print('CURRENT USER UID: ${FirebaseAuth.instance.currentUser?.uid}');

    final snapshot = await FirebaseFirestore.instance
        .collection('properties')
        .where('ownerId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
        .get();

    if (snapshot.docs.isNotEmpty) {
      final docs = snapshot.docs
          .cast<QueryDocumentSnapshot<Map<String, dynamic>>>()
          .toList();

      QueryDocumentSnapshot<Map<String, dynamic>>? primary;
      for (final d in docs) {
        if (d.id == 'euroescape') {
          primary = d;
        } else {
          print('WARNING: Duplicate property found: ${d.id}');
        }
      }
      primary ??= docs.first;
      final chosen = primary;
      final firstId = chosen.id;
      if (!mounted) return;
      setState(() {
        ownedProperties = docs;
        currentPropertyId = firstId;
        _hydratePropertyControllers(chosen.data(), fallbackId: firstId);
        _fetchCompleted = true;
      });
      print('Active Property ID: $currentPropertyId');
      await _loadPropertyData(firstId);
    } else {
      print('DEBUG: No properties found for this user UID.');
      if (mounted) setState(() => _fetchCompleted = true);
    }
  }

  /// Claims the first available property by setting its ownerId to current user.
  Future<void> _claimExistingProperty() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You must be signed in to claim a property.')));
      }
      return;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('properties')
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No properties exist in the database to claim.')));
        }
        return;
      }
      final docId = snapshot.docs.first.id;
      await FirebaseFirestore.instance
          .collection('properties')
          .doc(docId)
          .set({'ownerId': uid}, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Property claimed. Refreshing...')));
      }
      await _fetchOwnedProperties();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Claim failed: $e')));
      }
    }
  }

  @override
  void dispose() {
    slugController.dispose();
    extraPaxCtrl.dispose();
    maxBaseGuestsCtrl.dispose();
    extraPaxFeeCtrl.dispose();
    securityDepositCtrl.dispose();
    holidayNameCtrl.dispose();
    holidayDateCtrl.dispose();
    holiday8Ctrl.dispose();
    holiday10Ctrl.dispose();
    holiday12Ctrl.dispose();
    holiday22Ctrl.dispose();
    gcashCtrl.dispose();
    mayaCtrl.dispose();
    bankDetailsCtrl.dispose();
    towelCtrl.dispose();
    cleaningCtrl.dispose();
    extraTableCtrl.dispose();
    weekday8Ctrl.dispose();
    weekday12Ctrl.dispose();
    weekday22Ctrl.dispose();
    weekend8Ctrl.dispose();
    weekend12Ctrl.dispose();
    weekend22Ctrl.dispose();
    weekdayNewLabelCtrl.dispose();
    weekdayNewRateCtrl.dispose();
    weekendNewLabelCtrl.dispose();
    weekendNewRateCtrl.dispose();
    weekdayControllers.forEach((_, c) => c.dispose());
    weekendControllers.forEach((_, c) => c.dispose());
    super.dispose();
  }

  String _propId() => slugController.text.trim().isNotEmpty
      ? slugController.text.trim().toLowerCase()
      : (currentPropertyId ?? 'euroescape');

  void _hydratePropertyControllers(Map<String, dynamic> data,
      {String? fallbackId}) {
    slugController.text =
        (data['slug'] as String?) ?? fallbackId ?? slugController.text;
    gcashCtrl.text = (data['gcashNumber'] as String?) ?? '';
    mayaCtrl.text = (data['mayaNumber'] as String?) ?? '';
    bankDetailsCtrl.text = (data['bankDetails'] as String?) ?? '';

    final maxBaseRaw = data['maxBaseGuests'];
    if (maxBaseRaw != null) {
      maxBaseGuestsCtrl.text = maxBaseRaw.toString();
    } else if (maxBaseGuestsCtrl.text.isEmpty) {
      maxBaseGuestsCtrl.text = '1';
    }

    final extraPaxRaw = data['extraPaxFee'];
    if (extraPaxRaw != null) {
      extraPaxFeeCtrl.text = extraPaxRaw.toString();
    }

    towelCtrl.text = (data['addOns']?['towels']?.toString() ?? '');
    extraTableCtrl.text = (data['addOns']?['tables']?.toString() ?? '');
    cleaningCtrl.text = (data['cleaningFee']?.toString() ?? '');
    final secRaw = data['securityDeposit'];
    if (secRaw != null) {
      securityDepositCtrl.text = secRaw.toString();
    } else if (securityDepositCtrl.text.isEmpty) {
      securityDepositCtrl.text = '0';
    }

    final p = data['primaryColor'];
    final s = data['secondaryColor'];
    try {
      if (p is String && p.isNotEmpty) {
        primaryColor = ColorUtils.fromHex(p);
      }
    } catch (_) {}
    try {
      if (s is String && s.isNotEmpty) {
        secondaryColor = ColorUtils.fromHex(s);
      }
    } catch (_) {}
  }

  Future<void> _loadPropertyData(String propertyId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('properties')
          .doc(propertyId)
          .get();
      if (!snap.exists) return;
      final data = snap.data() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _hydratePropertyControllers(data, fallbackId: propertyId);

        // rebuild weekday/weekend duration controllers from Firestore maps
        weekdayControllers.forEach((_, c) => c.dispose());
        weekdayControllers.clear();
        weekendControllers.forEach((_, c) => c.dispose());
        weekendControllers.clear();

        final wr = data['weekdayRates'];
        if (wr is Map) {
          wr.forEach((k, v) {
            weekdayControllers[k.toString()] =
                TextEditingController(text: v?.toString() ?? '');
          });
        }
        final we = data['weekendRates'];
        if (we is Map) {
          we.forEach((k, v) {
            weekendControllers[k.toString()] =
                TextEditingController(text: v?.toString() ?? '');
          });
        }

        final sec = data['securityDeposit'];
        if (sec != null) {
          securityDepositCtrl.text = sec.toString();
        } else if (securityDepositCtrl.text.isEmpty) {
          securityDepositCtrl.text = '0';
        }
      });
    } catch (_) {
      // swallow errors in owner console to avoid breaking the dashboard
    }
  }

  void _pickHolidayDate() async {
    final d = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100));
    if (d != null) holidayDateCtrl.text = DateFormat('yyyy-MM-dd').format(d);
  }

  Widget _sidebar() {
    Widget _sideButton(String text, int idx, IconData icon) => InkWell(
        onTap: () => setState(() => _selectedIndex = idx),
        child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(text, style: GoogleFonts.poppins())
            ])));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      if (ownedProperties.isNotEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: DropdownButton<String>(
                isExpanded: true,
                value: currentPropertyId ?? ownedProperties.first.id,
                items: ownedProperties.map((d) {
                  final m = d.data();
                  final label =
                      (m['name'] as String?) ?? (m['slug'] as String?) ?? d.id;
                  return DropdownMenuItem(value: d.id, child: Text(label));
                }).toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  final sel = ownedProperties.firstWhere((d) => d.id == v,
                      orElse: () => ownedProperties.first);
                  final data = sel.data();
                  setState(() {
                    currentPropertyId = sel.id;
                    _hydratePropertyControllers(data, fallbackId: sel.id);
                    print('Active Property ID: $currentPropertyId');
                  });
                  await _loadPropertyData(sel.id);
                })),
      const SizedBox(height: 12),
      _sideButton('Live Bookings', 0, Icons.event),
      _sideButton('Property Settings', 1, Icons.home),
      _sideButton('Theme Decorator', 2, Icons.color_lens),
      _sideButton('Pricing Manager', 3, Icons.monetization_on),
    ]);
  }

  DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return DateFormat('MMM d, yyyy').format(d);
  }

  int _calcNights(Map<String, dynamic> booking, DateTime? checkIn,
      DateTime? checkOut) {
    if (checkIn != null && checkOut != null) {
      final n = checkOut.difference(checkIn).inDays;
      if (n > 0) return n;
    }
    final rawStayDates = booking['stayDates'];
    if (rawStayDates is List) {
      // BookingScreen passes a list of stay dates where length ~= nights
      if (rawStayDates.isNotEmpty) return rawStayDates.length;
    }
    return 0;
  }

  int? _parseDurationHours(String? v) {
    if (v == null) return null;
    final m = RegExp(r'(\d+)').firstMatch(v);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
  }

  String _normalizeStatus(dynamic raw) {
    final s = (raw ?? '').toString().toLowerCase().trim();
    if (s.contains('verify')) return 'verified';
    if (s.contains('reject')) return 'rejected';
    if (s.contains('pending')) return 'pending';
    if (s.isEmpty) return 'pending';
    return s;
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'verified':
        return Colors.green.shade600;
      case 'rejected':
        return Colors.red.shade600;
      default:
        return Colors.orange.shade700;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'verified':
        return 'Verified';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  Widget _statusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _statusBg(status),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabel(status),
        style: GoogleFonts.poppins(
            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  void _showImageDialog({required String title, required String? url}) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: GoogleFonts.poppins()),
        content: (url != null && url.isNotEmpty)
            ? InteractiveViewer(
                maxScale: 5,
                child: Image.network(url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Text('Image not available')),
              )
            : const Text('No image provided'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'))
        ],
      ),
    );
  }

  Widget _thumbnailTile(
      {required String label, required String? url, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 140,
        height: 90,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 56,
                height: 56,
                color: Colors.grey.shade100,
                child: (url != null && url.isNotEmpty)
                    ? Image.network(url, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image,
                              color: Colors.red,
                            ))
                    : Icon(Icons.image_not_supported,
                        color: Colors.grey.shade400),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _setBookingVerificationStatus(
      String bookingId, String status) async {
    final normalized = _normalizeStatus(status);
    try {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).set({
        'paymentStatus': normalized,
        'status': normalized,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking marked as ${_statusLabel(normalized)}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Widget _liveBookings() {
    // ID Check: ensure we have a valid property so the query doesn't fail
    debugPrint('_liveBookings currentPropertyId: $currentPropertyId');
    if (currentPropertyId == null || currentPropertyId!.isEmpty) {
      return Center(
          child: Text('Select a property to view bookings',
              style: GoogleFonts.poppins()));
    }
    final propId = _propId();

    // Query Strip: no orderBy so docs missing createdAt still appear
    // Field Match: checkout writes propertySlug; use same field here
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('propertySlug', isEqualTo: propId)
          .snapshots(),
      builder: (context, snapshot) {
        debugPrint('Bookings found: ${snapshot.data?.docs.length}');
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty)
          return const Center(child: Text('No active bookings found.'));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final b = docs[index].data();
            final bId = docs[index].id;

            // Guest name is stored as guestNames (list) in checkout; keep backward compat.
            final dynamic rawNames = b['guestNames'] ?? b['guestName'];
            String guestName = 'Guest';
            if (rawNames is List && rawNames.isNotEmpty) {
              guestName = rawNames.first?.toString() ?? 'Guest';
            } else if (rawNames != null && rawNames.toString().trim().isNotEmpty) {
              guestName = rawNames.toString();
            }

            final status = _normalizeStatus(b['paymentStatus'] ?? b['status']);

            final checkIn = _asDate(b['checkInDate'] ?? b['checkIn'] ?? b['startDate']);
            final checkOut = _asDate(b['checkOutDate'] ?? b['checkOut'] ?? b['endDate']);
            final nights = _calcNights(b, checkIn, checkOut);
            final hours = _parseDurationHours(b['selectedDuration']?.toString());
            final stayLabel = nights > 0
                ? 'Stay: $nights Night${nights == 1 ? '' : 's'}'
                : (hours != null ? 'Stay: $hours Hours' : 'Stay: —');

            final email = (b['guestEmail'] ?? b['email'] ?? '').toString();
            final phone = (b['guestPhone'] ?? b['phone'] ?? '').toString();

            // Image urls (checkout uses idUrls list + receiptUrl)
            String? idUrl;
            final rawIdUrls = b['idUrls'] ?? b['idUrl'] ?? b['guestIdPhoto'];
            if (rawIdUrls is List && rawIdUrls.isNotEmpty) {
              idUrl = rawIdUrls.first?.toString();
            } else if (rawIdUrls != null) {
              idUrl = rawIdUrls.toString();
            }
            final receiptUrl = (b['receiptUrl'] ?? b['proofOfPaymentUrl'])?.toString();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Card(
                    elevation: 2,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: LayoutBuilder(builder: (context, c) {
                        final isNarrow = c.maxWidth < 520;

                        final buttons = Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: isNarrow ? double.infinity : null,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.check),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                                onPressed: status == 'pending'
                                    ? () => _setBookingVerificationStatus(
                                        bId, 'verified')
                                    : null,
                                label: const Text('Verify Booking'),
                              ),
                            ),
                            SizedBox(
                              width: isNarrow ? double.infinity : null,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.close),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade50,
                                  foregroundColor: Colors.red.shade700,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  side: BorderSide(
                                      color: Colors.red.shade200, width: 1),
                                ),
                                onPressed: status == 'pending'
                                    ? () => _setBookingVerificationStatus(
                                        bId, 'rejected')
                                    : null,
                                label: const Text('Reject'),
                              ),
                            ),
                          ],
                        );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    guestName,
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                _statusChip(status),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Dates: Check-in: ${_fmtDate(checkIn)} to ${_fmtDate(checkOut)}',
                              style: GoogleFonts.poppins(
                                  fontSize: 13, color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              stayLabel,
                              style: GoogleFonts.poppins(
                                  fontSize: 13, color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Contact',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Email: ${email.isEmpty ? '—' : email}',
                              style: GoogleFonts.poppins(
                                  fontSize: 13, color: Colors.grey.shade800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Phone: ${phone.isEmpty ? '—' : phone}',
                              style: GoogleFonts.poppins(
                                  fontSize: 13, color: Colors.grey.shade800),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Verification',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                _thumbnailTile(
                                  label: 'Guest ID',
                                  url: idUrl,
                                  onTap: () => _showImageDialog(
                                      title: 'Guest ID', url: idUrl),
                                ),
                                _thumbnailTile(
                                  label: 'Proof of Payment',
                                  url: receiptUrl,
                                  onTap: () => _showImageDialog(
                                      title: 'Proof of Payment',
                                      url: receiptUrl),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            buttons,
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _propertySettings() {
    final propId = _propId();
    final docRef =
        FirebaseFirestore.instance.collection('properties').doc(propId);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Property: $propId',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        TextField(
            controller: slugController,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), hintText: 'enter property slug')),
        const SizedBox(height: 12),
        Text('Payment Setup',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
            controller: gcashCtrl,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'GCash Number')),
        const SizedBox(height: 8),
        TextField(
            controller: mayaCtrl,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'Maya Number')),
        const SizedBox(height: 8),
        TextField(
            controller: bankDetailsCtrl,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'Bank Details')),
        const SizedBox(height: 12),
        Row(children: [
          ElevatedButton(
              onPressed: () async {
                try {
                  await docRef.set({
                    'gcashNumber': gcashCtrl.text.trim(),
                    'mayaNumber': mayaCtrl.text.trim(),
                    'bankDetails': bankDetailsCtrl.text.trim(),
                    'updatedAt': FieldValue.serverTimestamp()
                  }, SetOptions(merge: true));
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Property payment settings saved')));
                } catch (e) {
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Save failed: $e')));
                }
              },
              child: const Text('Save Property Settings')),
          const SizedBox(width: 12),
          TextButton(
              onPressed: () => setState(() {
                    gcashCtrl.text = '';
                    mayaCtrl.text = '';
                    bankDetailsCtrl.text = '';
                  }),
              child: const Text('Clear'))
        ])
      ]),
    );
  }

  Widget _themeDecorator() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Primary Brand Color',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          GestureDetector(
              onTap: () => setState(() {
                    primaryColor = primaryColor == Colors.blue
                        ? Colors.deepPurple
                        : Colors.blue;
                  }),
              child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300)))),
          const SizedBox(width: 12),
          Expanded(
              child: Text('Live value: ${ColorUtils.toHex(primaryColor)}',
                  style: GoogleFonts.poppins()))
        ]),
        const SizedBox(height: 16),
        Text('Secondary Accents',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          GestureDetector(
              onTap: () => setState(() {
                    secondaryColor = secondaryColor == Colors.teal
                        ? Colors.orange
                        : Colors.teal;
                  }),
              child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                      color: secondaryColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300)))),
          const SizedBox(width: 12),
          Expanded(
              child: Text('Live value: ${ColorUtils.toHex(secondaryColor)}',
                  style: GoogleFonts.poppins()))
        ]),
        const SizedBox(height: 20),
        Row(children: [
          ElevatedButton(
              onPressed: isSavingTheme ? null : _saveThemeToEuroescape,
              child: isSavingTheme
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save & Apply')),
          const SizedBox(width: 12),
          TextButton(
              onPressed: () => setState(() {}),
              child: const Text('Reset to Remote'))
        ])
      ]),
    );
  }

  Future<void> _saveThemeToEuroescape() async {
    setState(() => isSavingTheme = true);
    try {
      final propId = _propId();
      final docRef =
          FirebaseFirestore.instance.collection('properties').doc(propId);
      await docRef.update({
        'primaryColor': ColorUtils.toHex(primaryColor),
        'secondaryColor': ColorUtils.toHex(secondaryColor)
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Theme saved to euroescape.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => isSavingTheme = false);
    }
  }

  void _addOrUpdateStagedHoliday() {
    final dateKey = holidayDateCtrl.text.trim();
    if (dateKey.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pick a holiday date first')));
      return;
    }
    final Map<String, dynamic> entry = {};
    final name = holidayNameCtrl.text.trim();
    if (name.isNotEmpty) entry['name'] = name;
    final Map<String, dynamic> rates = {};
    if (holiday8Ctrl.text.trim().isNotEmpty) {
      rates['8h'] =
          double.tryParse(holiday8Ctrl.text.replaceAll(',', '')) ?? 0.0;
    }
    if (holiday12Ctrl.text.trim().isNotEmpty) {
      rates['12h'] =
          double.tryParse(holiday12Ctrl.text.replaceAll(',', '')) ?? 0.0;
    }
    if (holiday22Ctrl.text.trim().isNotEmpty) {
      rates['22h'] =
          double.tryParse(holiday22Ctrl.text.replaceAll(',', '')) ?? 0.0;
    }
    entry['rates'] = rates;
    setState(() {
      stagedHolidayRates[dateKey] = entry;
      editingHolidayKey = null;
      holidayNameCtrl.clear();
      holidayDateCtrl.clear();
      holiday8Ctrl.clear();
      holiday12Ctrl.clear();
      holiday22Ctrl.clear();
    });
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Holiday added to list')));
  }

  void _deleteStagedHoliday(String key) {
    setState(() {
      stagedHolidayRates.remove(key);
      if (editingHolidayKey == key) editingHolidayKey = null;
    });
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Holiday removed')));
  }

  void _editStagedHoliday(String key) {
    final val = stagedHolidayRates[key];
    if (val == null) return;
    Map<String, dynamic> rates = {};
    final rawRates = val['rates'];
    if (rawRates is Map) {
      rates = Map<String, dynamic>.from(rawRates);
    } else {
      rates = Map<String, dynamic>.from(val);
      rates.remove('name');
    }
    setState(() {
      holidayNameCtrl.text = (val['name']?.toString() ?? '');
      holidayDateCtrl.text = key;
      holiday8Ctrl.text = (rates['8h']?.toString() ?? '');
      holiday12Ctrl.text = (rates['12h']?.toString() ?? '');
      holiday22Ctrl.text = (rates['22h']?.toString() ?? '');
      editingHolidayKey = key;
    });
  }

  Widget _pricingManager() {
    final propId = _propId();
    final docRef =
        FirebaseFirestore.instance.collection('properties').doc(propId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final data = snap.data!.data() ?? <String, dynamic>{};

        // seed dynamic duration controllers if empty
        if (weekdayControllers.isEmpty) {
          final raw = data['weekdayRates'] ?? {};
          try {
            if (raw is Map) {
              raw.forEach((k, v) {
                final key = k.toString();
                final val = v;
                final tc = TextEditingController(text: val?.toString() ?? '');
                weekdayControllers[key] = tc;
              });
            }
          } catch (_) {}
        }
        if (weekendControllers.isEmpty) {
          final raw = data['weekendRates'] ?? {};
          try {
            if (raw is Map) {
              raw.forEach((k, v) {
                final key = k.toString();
                final val = v;
                final tc = TextEditingController(text: val?.toString() ?? '');
                weekendControllers[key] = tc;
              });
            }
          } catch (_) {}
        }
        if (holidayNameCtrl.text.isEmpty)
          holidayNameCtrl.text = (data['holidayName'] as String?) ?? '';
        if (holidayDateCtrl.text.isEmpty)
          holidayDateCtrl.text = (data['holidayDate'] as String?) ?? '';

        if (extraPaxCtrl.text.isEmpty)
          extraPaxCtrl.text = (data['extraPaxFee']?.toString() ?? '');
        if (maxBaseGuestsCtrl.text.isEmpty)
          maxBaseGuestsCtrl.text = (data['maxBaseGuests']?.toString() ?? '1');
        if (extraPaxFeeCtrl.text.isEmpty)
          extraPaxFeeCtrl.text = (data['extraPaxFee']?.toString() ?? '');
        if (towelCtrl.text.isEmpty)
          towelCtrl.text = (data['addOns']?['towels']?.toString() ?? '');
        if (extraTableCtrl.text.isEmpty)
          extraTableCtrl.text = (data['addOns']?['tables']?.toString() ?? '');
        if (cleaningCtrl.text.isEmpty)
          cleaningCtrl.text = (data['cleaningFee']?.toString() ?? '');
        if (securityDepositCtrl.text.isEmpty)
          securityDepositCtrl.text =
              (data['securityDeposit']?.toString() ?? '0');

        // seed stagedHolidayRates from remote if not already staged
        if (stagedHolidayRates.isEmpty) {
          final raw = data['holidayRates'] ?? {};
          try {
            if (raw is Map) {
              raw.forEach((k, v) {
                if (k is String && v is Map) {
                  stagedHolidayRates[k] = Map<String, dynamic>.from(v);
                }
              });
            }
          } catch (_) {}
        }

        return DefaultTabController(
          length: 3,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pricing Manager',
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TabBar(
              tabs: const [
                Tab(text: 'Standard'),
                Tab(text: 'Holidays'),
                Tab(text: 'Add-Ons')
              ],
              labelColor: primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: primaryColor,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(children: [
                // Standard
                SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(children: [
                      // Weekday dynamic durations
                      Expanded(
                          child: Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Weekday Rates',
                                            style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 8),
                                        Row(children: [
                                          SizedBox(
                                              width: 140,
                                              child: TextField(
                                                  controller:
                                                      weekdayNewLabelCtrl,
                                                  decoration: const InputDecoration(
                                                      labelText:
                                                          'Duration (e.g., 6h)'))),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                              width: 140,
                                              child: TextField(
                                                  controller:
                                                      weekdayNewRateCtrl,
                                                  keyboardType: TextInputType
                                                      .numberWithOptions(
                                                          decimal: true),
                                                  decoration:
                                                      const InputDecoration(
                                                          labelText:
                                                              'Rate (₱)'))),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                              onPressed: () {
                                                final label =
                                                    weekdayNewLabelCtrl.text
                                                        .trim();
                                                final rate = weekdayNewRateCtrl
                                                    .text
                                                    .trim();
                                                if (label.isEmpty ||
                                                    rate.isEmpty) {
                                                  if (mounted)
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                            const SnackBar(
                                                                content: Text(
                                                                    'Enter duration and rate')));
                                                  return;
                                                }
                                                setState(() {
                                                  // update existing key or add new
                                                  if (editingWeekdayKey !=
                                                      null) {
                                                    // remove old key if changed
                                                    if (editingWeekdayKey !=
                                                        label) {
                                                      final old =
                                                          weekdayControllers.remove(
                                                              editingWeekdayKey);
                                                      old?.dispose();
                                                    }
                                                    weekdayControllers[label] =
                                                        TextEditingController(
                                                            text: rate);
                                                    editingWeekdayKey = null;
                                                  } else {
                                                    weekdayControllers[label] =
                                                        TextEditingController(
                                                            text: rate);
                                                  }
                                                  weekdayNewLabelCtrl.clear();
                                                  weekdayNewRateCtrl.clear();
                                                });
                                              },
                                              child: Text(
                                                  editingWeekdayKey == null
                                                      ? 'Add'
                                                      : 'Update'))
                                        ]),
                                        const SizedBox(height: 12),
                                        // list durations
                                        if (weekdayControllers.isNotEmpty)
                                          Column(
                                              children: weekdayControllers
                                                  .entries
                                                  .map((e) => Card(
                                                        margin: const EdgeInsets
                                                            .symmetric(
                                                            vertical: 6),
                                                        child: ListTile(
                                                          title: Text(e.key),
                                                          subtitle: Text(
                                                              e.value.text),
                                                          trailing: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                IconButton(
                                                                    icon: const Icon(
                                                                        Icons
                                                                            .edit),
                                                                    onPressed:
                                                                        () {
                                                                      setState(
                                                                          () {
                                                                        weekdayNewLabelCtrl.text =
                                                                            e.key;
                                                                        weekdayNewRateCtrl.text = e
                                                                            .value
                                                                            .text;
                                                                        editingWeekdayKey =
                                                                            e.key;
                                                                      });
                                                                    }),
                                                                IconButton(
                                                                    icon: const Icon(
                                                                        Icons
                                                                            .delete),
                                                                    onPressed:
                                                                        () {
                                                                      setState(
                                                                          () {
                                                                        final old =
                                                                            weekdayControllers.remove(e.key);
                                                                        old?.dispose();
                                                                      });
                                                                    })
                                                              ]),
                                                        ),
                                                      ))
                                                  .toList())
                                      ])))),
                      const SizedBox(width: 12),
                      // Weekend dynamic durations
                      Expanded(
                          child: Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Weekend Rates',
                                            style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 8),
                                        Row(children: [
                                          SizedBox(
                                              width: 140,
                                              child: TextField(
                                                  controller:
                                                      weekendNewLabelCtrl,
                                                  decoration: const InputDecoration(
                                                      labelText:
                                                          'Duration (e.g., 6h)'))),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                              width: 140,
                                              child: TextField(
                                                  controller:
                                                      weekendNewRateCtrl,
                                                  keyboardType: TextInputType
                                                      .numberWithOptions(
                                                          decimal: true),
                                                  decoration:
                                                      const InputDecoration(
                                                          labelText:
                                                              'Rate (₱)'))),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                              onPressed: () {
                                                final label =
                                                    weekendNewLabelCtrl.text
                                                        .trim();
                                                final rate = weekendNewRateCtrl
                                                    .text
                                                    .trim();
                                                if (label.isEmpty ||
                                                    rate.isEmpty) {
                                                  if (mounted)
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                            const SnackBar(
                                                                content: Text(
                                                                    'Enter duration and rate')));
                                                  return;
                                                }
                                                setState(() {
                                                  if (editingWeekendKey !=
                                                      null) {
                                                    if (editingWeekendKey !=
                                                        label) {
                                                      final old =
                                                          weekendControllers.remove(
                                                              editingWeekendKey);
                                                      old?.dispose();
                                                    }
                                                    weekendControllers[label] =
                                                        TextEditingController(
                                                            text: rate);
                                                    editingWeekendKey = null;
                                                  } else {
                                                    weekendControllers[label] =
                                                        TextEditingController(
                                                            text: rate);
                                                  }
                                                  weekendNewLabelCtrl.clear();
                                                  weekendNewRateCtrl.clear();
                                                });
                                              },
                                              child: Text(
                                                  editingWeekendKey == null
                                                      ? 'Add'
                                                      : 'Update'))
                                        ]),
                                        const SizedBox(height: 12),
                                        if (weekendControllers.isNotEmpty)
                                          Column(
                                              children: weekendControllers
                                                  .entries
                                                  .map((e) => Card(
                                                        margin: const EdgeInsets
                                                            .symmetric(
                                                            vertical: 6),
                                                        child: ListTile(
                                                          title: Text(e.key),
                                                          subtitle: Text(
                                                              e.value.text),
                                                          trailing: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                IconButton(
                                                                    icon: const Icon(
                                                                        Icons
                                                                            .edit),
                                                                    onPressed:
                                                                        () {
                                                                      setState(
                                                                          () {
                                                                        weekendNewLabelCtrl.text =
                                                                            e.key;
                                                                        weekendNewRateCtrl.text = e
                                                                            .value
                                                                            .text;
                                                                        editingWeekendKey =
                                                                            e.key;
                                                                      });
                                                                    }),
                                                                IconButton(
                                                                    icon: const Icon(
                                                                        Icons
                                                                            .delete),
                                                                    onPressed:
                                                                        () {
                                                                      setState(
                                                                          () {
                                                                        final old =
                                                                            weekendControllers.remove(e.key);
                                                                        old?.dispose();
                                                                      });
                                                                    })
                                                              ]),
                                                        ),
                                                      ))
                                                  .toList())
                                      ]))))
                    ]),
                  ),
                ),

                // Holidays
                SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Holiday Setup',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            TextField(
                                controller: holidayNameCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Holiday Name')),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                  child: TextField(
                                      controller: holidayDateCtrl,
                                      readOnly: true,
                                      decoration: const InputDecoration(
                                          labelText: 'Holiday Date'))),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                  onPressed: _pickHolidayDate,
                                  child: const Text('Pick Date'))
                            ]),
                            const SizedBox(height: 12),
                            Text('Holiday Rates',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              SizedBox(
                                  width: 140,
                                  child: TextField(
                                      controller: holiday8Ctrl,
                                      keyboardType:
                                          TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                          labelText: '8H (₱)'))),
                              SizedBox(
                                  width: 140,
                                  child: TextField(
                                      controller: holiday12Ctrl,
                                      keyboardType:
                                          TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                          labelText: '12H (₱)'))),
                              SizedBox(
                                  width: 140,
                                  child: TextField(
                                      controller: holiday22Ctrl,
                                      keyboardType:
                                          TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                          labelText: '22H (₱)'))),
                            ]),
                            const SizedBox(height: 12),
                            Row(children: [
                              ElevatedButton(
                                onPressed: _addOrUpdateStagedHoliday,
                                child: Text(editingHolidayKey == null
                                    ? 'Add Holiday'
                                    : 'Update Holiday'),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: () {
                                  holidayNameCtrl.clear();
                                  holidayDateCtrl.clear();
                                  holiday8Ctrl.clear();
                                  holiday12Ctrl.clear();
                                  holiday22Ctrl.clear();
                                  setState(() {
                                    editingHolidayKey = null;
                                  });
                                },
                                child: const Text('Clear'),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            // list staged holidays
                            if (stagedHolidayRates.isNotEmpty)
                              Column(children: [
                                for (final e in stagedHolidayRates.entries)
                                  Card(
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    child: ListTile(
                                      title: Text(
                                          e.value['name']?.toString() ?? e.key),
                                      subtitle: Text(e.key),
                                      trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                                icon: const Icon(Icons.edit),
                                                onPressed: () =>
                                                    _editStagedHoliday(e.key)),
                                            IconButton(
                                                icon: const Icon(Icons.delete),
                                                onPressed: () =>
                                                    _deleteStagedHoliday(
                                                        e.key)),
                                          ]),
                                    ),
                                  )
                              ])
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Add-Ons
                SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Add-Ons (Revenue Maximizer)',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                  child: TextField(
                                      controller: maxBaseGuestsCtrl,
                                      keyboardType:
                                          TextInputType.numberWithOptions(
                                              decimal: false),
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Base Guests Included in Price'))),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: TextField(
                                      controller: extraPaxFeeCtrl,
                                      keyboardType:
                                          TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Extra Pax Fee (per head) (₱)'))),
                            ]),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                  child: TextField(
                                      controller: towelCtrl,
                                      keyboardType:
                                          TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                          labelText: 'Towel Fee (₱)'))),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: TextField(
                                      controller: cleaningCtrl,
                                      keyboardType:
                                          TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                          labelText: 'Cleaning Fee (₱)'))),
                            ]),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                  child: TextField(
                                      controller: extraTableCtrl,
                                      keyboardType:
                                          TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                          labelText: 'Extra Table Fee (₱)'))),
                            ]),
                            const SizedBox(height: 8),
                            // Security deposit field
                            Row(children: [
                              Expanded(
                                  child: TextField(
                                      controller: securityDepositCtrl,
                                      keyboardType:
                                          TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Security Deposit (Refundable) (₱)'))),
                            ]),
                            const SizedBox(height: 12),
                            Row(children: [
                              ElevatedButton(
                                onPressed: () async {
                                  final Map<String, dynamic> weekday = {};
                                  final Map<String, dynamic> weekend = {};
                                  // build maps from dynamic controllers
                                  weekdayControllers.forEach((k, c) {
                                    final v = double.tryParse(
                                            c.text.replaceAll(',', '')) ??
                                        0.0;
                                    weekday[k] = v;
                                  });
                                  weekendControllers.forEach((k, c) {
                                    final v = double.tryParse(
                                            c.text.replaceAll(',', '')) ??
                                        0.0;
                                    weekend[k] = v;
                                  });
                                  final Map<String, dynamic> addOns = {
                                    'towels': double.tryParse(towelCtrl.text
                                            .replaceAll(',', '')) ??
                                        0.0,
                                    'tables': double.tryParse(extraTableCtrl
                                            .text
                                            .replaceAll(',', '')) ??
                                        0.0
                                  };
                                  final Map<String, dynamic> holidayRateUpdates =
                                      {};
                                  stagedHolidayRates.forEach((dateKey, val) {
                                    Map<String, dynamic> payload = {};
                                    Map<String, dynamic> rates = {};
                                    if (val['rates'] is Map) {
                                      rates = Map<String, dynamic>.from(
                                          val['rates'] as Map);
                                      if (val['name'] != null) {
                                        payload['name'] =
                                            val['name'].toString();
                                      }
                                    } else {
                                      final flat =
                                          Map<String, dynamic>.from(val);
                                      final name = flat.remove('name');
                                      if (name != null) {
                                        payload['name'] = name.toString();
                                      }
                                      rates = flat;
                                    }
                                    payload['rates'] = rates;
                                    holidayRateUpdates['holidayRates.$dateKey'] =
                                        payload;
                                  });
                                  try {
                                    await docRef.set({
                                      'weekdayRates': weekday,
                                      'weekendRates': weekend,
                                      'maxBaseGuests': int.tryParse(
                                              maxBaseGuestsCtrl.text
                                                  .replaceAll(',', '')) ??
                                          1,
                                      'extraPaxFee': double.tryParse(
                                              extraPaxFeeCtrl.text
                                                  .replaceAll(',', '')) ??
                                          0.0,
                                      'cleaningFee': double.tryParse(
                                              cleaningCtrl.text
                                                  .replaceAll(',', '')) ??
                                          0.0,
                                      'securityDeposit': double.tryParse(
                                              securityDepositCtrl.text) ??
                                          0.0,
                                      'addOns': addOns,
                                      'holidayDates': FieldValue.arrayUnion(
                                          stagedHolidayRates.keys.toList()),
                                      ...holidayRateUpdates,
                                    }, SetOptions(merge: true));
                                    if (mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text('Pricing saved')));
                                  } catch (e) {
                                    if (mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content:
                                                  Text('Save failed: $e')));
                                  }
                                },
                                child: const Text('Save Pricing'),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: () {
                                  // clear dynamic duration controllers
                                  weekdayControllers.forEach((k, c) {
                                    c.dispose();
                                  });
                                  weekdayControllers.clear();
                                  weekendControllers.forEach((k, c) {
                                    c.dispose();
                                  });
                                  weekendControllers.clear();
                                  weekdayNewLabelCtrl.clear();
                                  weekdayNewRateCtrl.clear();
                                  weekendNewLabelCtrl.clear();
                                  weekendNewRateCtrl.clear();
                                  extraPaxCtrl.clear();
                                  towelCtrl.clear();
                                  extraTableCtrl.clear();
                                  cleaningCtrl.clear();
                                },
                                child: const Text('Clear'),
                              ),
                            ])
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            )
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    print('Active Property ID: $currentPropertyId');

    // UI Guard: wait for properties to load before showing dashboard
    if (!_fetchCompleted) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Fetching your properties...',
                  style: GoogleFonts.poppins()),
            ],
          ),
        ),
      );
    }

    // Force Link: when fetch completed but no properties, show claim button
    if (currentPropertyId == null && ownedProperties.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Owner Dashboard',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('No properties linked to your account.',
                    style: GoogleFonts.poppins(fontSize: 16),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                    'If a property already exists (e.g. euroescape), you can claim it below.',
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _claimExistingProperty,
                  icon: const Icon(Icons.add_home_work),
                  label: const Text('Claim Existing Property'),
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget content;
    switch (_selectedIndex) {
      case 0:
        content = _liveBookings();
        break;
      case 1:
        content = _propertySettings();
        break;
      case 2:
        content = _themeDecorator();
        break;
      case 3:
      default:
        content = _pricingManager();
    }

    return LayoutBuilder(builder: (context, constraints) {
      final bool isMobile = constraints.maxWidth < 700;
      if (isMobile) {
        return Scaffold(
            appBar: AppBar(
                title: Text('Owner Dashboard',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700))),
            drawer: Drawer(child: _sidebar()),
            body: SafeArea(
                child: Column(
              children: [
                if (currentPropertyId == null && ownedProperties.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('Please select a property to manage',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500)),
                  ),
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.all(8.0), child: content)),
              ],
            )));
      }
      return Scaffold(
          body: Row(children: [
        SizedBox(width: 260, child: _sidebar()),
        Expanded(
            child: Column(
          children: [
            if (currentPropertyId == null && ownedProperties.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Please select a property to manage',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500)),
                ),
              ),
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.all(12.0), child: content)),
          ],
        ))
      ]));
    });
  }
}
