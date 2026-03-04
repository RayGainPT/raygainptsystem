import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'performance_dashboard.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
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
  int _selectedIndex = 0;
  DateTime? _bookingFilterDate;

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
  final TextEditingController propertyLabelCtrl = TextEditingController();
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

  List<DocumentSnapshot<Map<String, dynamic>>> ownedProperties = [];
  String? currentPropertyId;
  bool _fetchCompleted = false;
  bool _uploadingPhotos = false;
  double _uploadPhotoProgress = 0.0;
  // staged holidays map: dateString -> { 'name': ..., '8h':..., '12h':..., '22h':... }
  final Map<String, Map<String, dynamic>> stagedHolidayRates = {};
  String? editingHolidayKey;

  Future<void> _deletePropertyPhoto(String url) async {
    final propId = _propId();
    final slugText = slugController.text.trim().toLowerCase();
    final String photoDocKey =
        slugText.isNotEmpty ? slugText : propId;
    if (photoDocKey.isEmpty) return;
    try {
      final docRef =
          FirebaseFirestore.instance.collection('properties').doc(photoDocKey);
      await docRef.update({
        'images': FieldValue.arrayRemove([url]),
        'propertyPhotos': FieldValue.arrayRemove([url]),
        'photos': FieldValue.arrayRemove([url]),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove photo: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.slug != null) slugController.text = widget.slug!;
    _fetchOwnedProperties();
  }

  Future<void> _showCreatePropertyDialog() async {
    final nameCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final slugCtrlLocal = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Create New Property', style: GoogleFonts.poppins()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Property Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: locationCtrl,
                decoration:
                    const InputDecoration(labelText: 'Location (city, area)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: slugCtrlLocal,
                decoration: const InputDecoration(
                    labelText: 'Slug (optional, e.g. euroescape)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () async {
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('You must be signed in to add a property')));
                    return;
                  }
                  final name = nameCtrl.text.trim();
                  final location = locationCtrl.text.trim();
                  String slug = slugCtrlLocal.text.trim();
                  if (slug.isEmpty) {
                    slug = name.toLowerCase().replaceAll(
                        RegExp(r'[^a-z0-9]+'), '-'); // simple slugify
                    slug = slug.replaceAll(RegExp(r'-+'), '-').trim();
                    if (slug.endsWith('-')) {
                      slug = slug.substring(0, slug.length - 1);
                    }
                  }
                  if (slug.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Provide at least a name or slug')));
                    return;
                  }
                  try {
                    final docRef = FirebaseFirestore.instance
                        .collection('properties')
                        .doc(slug);
                    await docRef.set({
                      'ownerId': uid,
                      'slug': slug,
                      'name': name.isNotEmpty ? name : slug,
                      'propertyLabel': name.isNotEmpty ? name : slug,
                      'location': location,
                      'createdAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
                    Navigator.of(context).pop();
                    // Refresh list & select new property
                    await _fetchOwnedProperties();
                    setState(() {
                      currentPropertyId = slug;
                      slugController.text = slug;
                    });
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Create failed: $e')));
                  }
                },
                child: const Text('Create')),
          ],
        );
      },
    );
  }

  /// Fetches properties for the current user and locks the first as selected.
  /// Firestore field used: ownerId (matches property model and pdf_service).
  /// Always sets _fetchCompleted so the UI never hangs on "Fetching your properties...".
  Future<void> _fetchOwnedProperties() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    print('CURRENT USER UID: $uid');

    if (uid == null || uid.isEmpty) {
      if (mounted) setState(() => _fetchCompleted = true);
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('properties')
          .where('ownerId', isEqualTo: uid)
          .get()
          .timeout(const Duration(seconds: 15),
              onTimeout: () => throw TimeoutException('Properties load timed out'));

      if (!mounted) return;
      if (snapshot.docs.isEmpty) {
        print('DEBUG: No properties found for this user UID.');
        setState(() => _fetchCompleted = true);
        return;
      }

      final docs = snapshot.docs
          .cast<DocumentSnapshot<Map<String, dynamic>>>()
          .toList();

      DocumentSnapshot<Map<String, dynamic>>? primary;
      for (final d in docs) {
        if (d.id == 'euroescape') {
          primary = d;
          break;
        }
      }
      primary ??= docs.first;
      final chosen = primary;
      final firstId = chosen.id;

      setState(() {
        ownedProperties = docs;
        currentPropertyId = firstId;
        _hydratePropertyControllers(chosen.data() ?? {}, fallbackId: firstId);
        _fetchCompleted = true;
      });
      print('Active Property ID: $currentPropertyId');
      await _loadPropertyData(firstId);
    } catch (e, st) {
      print('_fetchOwnedProperties error: $e');
      print(st);
      if (mounted) {
        // Fallback: if URL has a slug (e.g. /dashboard/euroescape), try opening that property by doc id
        final opened = await _tryOpenPropertyBySlug(uid);
        setState(() => _fetchCompleted = true);
        if (!opened) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not load properties. Check connection or Firestore rules.'),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: _fetchOwnedProperties,
              ),
            ),
          );
        }
      }
    }
  }

  /// When the list query fails or returns empty, try to open the property by slug from the URL.
  /// Returns true if we opened a property so the dashboard can show.
  Future<bool> _tryOpenPropertyBySlug(String uid) async {
    final slug = widget.slug?.trim();
    if (slug == null || slug.isEmpty) return false;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('properties')
          .doc(slug)
          .get()
          .timeout(const Duration(seconds: 10));
      if (!doc.exists || doc.data() == null) return false;
      final data = doc.data()!;
      final docOwnerId = data['ownerId']?.toString();
      if (docOwnerId != uid) return false;
      if (!mounted) return true;
      setState(() {
        ownedProperties = [doc];
        currentPropertyId = slug;
        _hydratePropertyControllers(data, fallbackId: slug);
      });
      _loadPropertyData(slug);
      return true;
    } catch (_) {
      return false;
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

  String _propId() {
    if (currentPropertyId != null && currentPropertyId!.isNotEmpty) {
      // Always prefer the actual Firestore document id for lookups
      return currentPropertyId!;
    }
    final slugText = slugController.text.trim();
    if (slugText.isNotEmpty) {
      return slugText.toLowerCase();
    }
    // Fallback for very first load / legacy case
    return 'euroescape';
  }

  /// Key used for guest-facing data: booking page and checkout use the slug.
  /// Use this for Live Bookings query, Pricing Manager, and Property Settings
  /// so the dashboard and booking page see the same property document.
  String _guestPropertyKey() {
    final slug = slugController.text.trim().toLowerCase();
    if (slug.isNotEmpty) return slug;
    return _propId();
  }

  void _hydratePropertyControllers(Map<String, dynamic> data,
      {String? fallbackId}) {
    slugController.text =
        (data['slug'] as String?) ?? fallbackId ?? slugController.text;
    propertyLabelCtrl.text =
        (data['propertyLabel'] as String?) ?? (data['name'] as String?) ?? '';
    gcashCtrl.text = (data['gcashNumber'] as String?) ?? '';
    mayaCtrl.text = (data['mayaNumber'] as String?) ?? '';
    bankDetailsCtrl.text = (data['bankDetails'] as String?) ?? '';

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
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add_home),
            label: const Text('Create New Property'),
            onPressed: _showCreatePropertyDialog,
          ),
        ),
      ),
      if (ownedProperties.isNotEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: DropdownButton<String>(
                isExpanded: true,
                value: currentPropertyId ?? ownedProperties.first.id,
                items: ownedProperties.map((d) {
                  final m = d.data();
                  final label = (m?['name'] as String?) ??
                      (m?['propertyLabel'] as String?) ??
                      (m?['slug'] as String?) ??
                      d.id;
                  return DropdownMenuItem(value: d.id, child: Text(label));
                }).toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  final sel = ownedProperties.firstWhere((d) => d.id == v,
                      orElse: () => ownedProperties.first);
                  setState(() {
                    currentPropertyId = sel.id;
                    _hydratePropertyControllers(sel.data() ?? {}, fallbackId: sel.id);
                    print('Active Property ID: $currentPropertyId');
                  });
                  await _loadPropertyData(sel.id);
                })),
      const SizedBox(height: 12),
      _sideButton('Performance', 0, Icons.insights),
      _sideButton('Manage Bookings', 1, Icons.event),
      _sideButton('Property Settings', 2, Icons.home),
      _sideButton('Theme Decorator', 3, Icons.color_lens),
      _sideButton('Pricing Manager', 4, Icons.monetization_on),
      const Spacer(),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.logout),
        title: Text('Logout', style: GoogleFonts.poppins()),
        onTap: () async {
          try {
            await FirebaseAuth.instance.signOut();
          } catch (_) {}
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil(
                '/', (route) => false);
          }
        },
      ),
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
    // Use slug so we match bookings (checkout saves propertySlug from URL slug)
    final guestKey = _guestPropertyKey();

    // Query Strip: no orderBy so docs missing createdAt still appear
    // Field Match: checkout writes propertySlug; use same field here
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('propertySlug', isEqualTo: guestKey)
          .snapshots(),
      builder: (context, snapshot) {
        debugPrint('Bookings found: ${snapshot.data?.docs.length}');
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        // Sort newest bookings first using createdAt when available
        final allDocs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final ad = a.data();
            final bd = b.data();
            final ca = ad['createdAt'];
            final cb = bd['createdAt'];
            if (ca is Timestamp && cb is Timestamp) {
              return cb.compareTo(ca); // descending
            }
            if (ca is Timestamp) return -1;
            if (cb is Timestamp) return 1;
            return 0;
          });
        // Optional date filter from performance calendar
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
            allDocs;
        final filterDate = _bookingFilterDate != null
            ? DateTime(_bookingFilterDate!.year,
                _bookingFilterDate!.month,
                _bookingFilterDate!.day)
            : null;
        if (filterDate != null) {
          docs = allDocs.where((d) {
            final b = d.data();
            final checkIn = _asDate(
                b['checkInDate'] ?? b['checkIn'] ?? b['startDate']);
            final checkOut = _asDate(
                b['checkOutDate'] ?? b['checkOut'] ?? b['endDate']);
            if (checkIn == null && checkOut == null) return false;

            final startDay = checkIn != null
                ? DateTime(checkIn.year, checkIn.month, checkIn.day)
                : null;
            final endDay = checkOut != null
                ? DateTime(checkOut.year, checkOut.month, checkOut.day)
                : null;

            // If we only know a single day (or check-in == check-out), treat that day as occupied.
            if (startDay != null &&
                (endDay == null || !endDay.isAfter(startDay))) {
              return startDay.year == filterDate.year &&
                  startDay.month == filterDate.month &&
                  startDay.day == filterDate.day;
            }

            // Normal multi-day range: [startDay, endDay)
            if (startDay != null && endDay != null) {
              var cursor = startDay;
              while (cursor.isBefore(endDay)) {
                if (cursor.year == filterDate.year &&
                    cursor.month == filterDate.month &&
                    cursor.day == filterDate.day) {
                  return true;
                }
                cursor = cursor.add(const Duration(days: 1));
              }
            }
            return false;
          }).toList();
        }
        if (docs.isEmpty) {
          return Center(
              child: Text(
                  filterDate == null
                      ? 'No active bookings found.'
                      : 'No bookings found for this date.',
                  style: GoogleFonts.poppins()));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final b = docs[index].data();
            final bId = docs[index].id;

            // Guest names stored as guestNames (list); keep backward compat.
            final dynamic rawNames = b['guestNames'] ?? b['guestName'];
            final List<String> guestNames = <String>[];
            String guestName = 'Guest';
            if (rawNames is List && rawNames.isNotEmpty) {
              for (final n in rawNames) {
                if (n == null) continue;
                final s = n.toString().trim();
                if (s.isNotEmpty) guestNames.add(s);
              }
              if (guestNames.isNotEmpty) {
                guestName = guestNames.first;
              }
            } else if (rawNames != null && rawNames.toString().trim().isNotEmpty) {
              final s = rawNames.toString().trim();
              guestName = s;
              guestNames.add(s);
            }

            final status = _normalizeStatus(b['paymentStatus'] ?? b['status']);

            final checkIn = _asDate(b['checkInDate'] ?? b['checkIn'] ?? b['startDate']);
            final checkOut = _asDate(b['checkOutDate'] ?? b['checkOut'] ?? b['endDate']);
            final nights = _calcNights(b, checkIn, checkOut);
            final hours = _parseDurationHours(b['selectedDuration']?.toString());
            final stayLabel = nights > 0
                ? 'Stay: $nights Night${nights == 1 ? '' : 's'}'
                : (hours != null ? 'Stay: $hours Hours' : 'Stay: —');

            String email = (b['guestEmail'] ?? b['email'] ?? '').toString();
            String phone = (b['guestPhone'] ?? b['phone'] ?? '').toString();
            // Fallback to first entry in guestEmails/guestPhones arrays if present
            final rawEmails = b['guestEmails'];
            if (email.isEmpty && rawEmails is List && rawEmails.isNotEmpty) {
              final first = rawEmails.first;
              if (first != null) email = first.toString();
            }
            final rawPhones = b['guestPhones'];
            if (phone.isEmpty && rawPhones is List && rawPhones.isNotEmpty) {
              final first = rawPhones.first;
              if (first != null) phone = first.toString();
            }

            // Image urls (checkout uses idUrls list + receiptUrl)
            final List<String> idUrls = <String>[];
            final rawIdUrls = b['idUrls'] ?? b['idUrl'] ?? b['guestIdPhoto'];
            if (rawIdUrls is List && rawIdUrls.isNotEmpty) {
              for (final v in rawIdUrls) {
                if (v == null) continue;
                final s = v.toString().trim();
                if (s.isNotEmpty) idUrls.add(s);
              }
            } else if (rawIdUrls != null) {
              final s = rawIdUrls.toString().trim();
              if (s.isNotEmpty) idUrls.add(s);
            }
            // Keep first ID in case we want to extend summary views later
            // (currently unused in the UI)
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
                            if (guestNames.isNotEmpty) ...[
                              Text(
                                'Guests & IDs',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: List.generate(guestNames.length,
                                    (i) {
                                  final name = guestNames[i];
                                  final String? guestIdUrl = (i < idUrls.length)
                                      ? idUrls[i]
                                      : null;
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 4.0),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: GoogleFonts.poppins(
                                                fontSize: 13,
                                                color: Colors
                                                    .grey.shade800),
                                          ),
                                        ),
                                        if (guestIdUrl != null &&
                                            guestIdUrl.isNotEmpty)
                                          InkWell(
                                            onTap: () => _showImageDialog(
                                                title: 'Guest ID - $name',
                                                url: guestIdUrl),
                                            child: Row(
                                              mainAxisSize:
                                                  MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.badge,
                                                    size: 18,
                                                    color:
                                                        Colors.blueGrey),
                                                const SizedBox(width: 4),
                                                Text('View ID',
                                                    style:
                                                        GoogleFonts.poppins(
                                                            fontSize: 12,
                                                            color: Colors
                                                                .blueGrey)),
                                              ],
                                            ),
                                          )
                                        else
                                          Text('No ID',
                                              style: GoogleFonts.poppins(
                                                  fontSize: 12,
                                                  color: Colors
                                                      .grey.shade500)),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 12),
                            ],
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
    final slugText = slugController.text.trim().toLowerCase();
    // For assets like photos that guests see, prefer the slug-based document
    // so Property Settings stays in sync with the public booking page.
    final String photoDocKey =
        slugText.isNotEmpty ? slugText : propId;
    final docRef = FirebaseFirestore.instance
        .collection('properties')
        .doc(photoDocKey);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final dynamic rawImages =
            data['images'] ?? data['propertyPhotos'] ?? data['photos'] ?? [];
        final List<String> imageUrls = <String>[];
        if (rawImages is List) {
          for (final v in rawImages) {
            if (v == null) continue;
            final s = v.toString().trim();
            if (s.isNotEmpty) imageUrls.add(s);
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('Property: $propId',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
                controller: propertyLabelCtrl,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Property Label (shown on booking page)',
                    hintText: 'e.g. Baguio Staycation')),
            const SizedBox(height: 12),
            TextField(
                controller: slugController,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'enter property slug')),
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
            const SizedBox(height: 16),
            Text('Property Photos',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (_uploadingPhotos) ...[
              LinearProgressIndicator(value: _uploadPhotoProgress),
              const SizedBox(height: 8),
              Text('Uploading photos…',
                  style: GoogleFonts.poppins(color: Colors.grey.shade700)),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _uploadingPhotos
                      ? null
                      : () async {
                          final propId = _propId();
                          if (propId.isEmpty) return;
                          try {
                            final result = await FilePicker.platform.pickFiles(
                              allowMultiple: true,
                              // Restrict to formats Flutter web renders reliably
                              type: FileType.custom,
                              allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
                              withData: true,
                            );
                            if (result == null || result.files.isEmpty) return;
                            final storage = FirebaseStorage.instance;
                            final List<String> newUrls = [];
                            final files = result.files
                                .where((f) => f.bytes != null)
                                .toList();
                            if (files.isEmpty) return;
                            if (mounted) {
                              setState(() {
                                _uploadingPhotos = true;
                                _uploadPhotoProgress = 0.0;
                              });
                            }
                            for (int i = 0; i < files.length; i++) {
                              final file = files[i];
                              final bytes = file.bytes!;
                              final filename =
                                  '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
                              final ref = storage
                                  .ref()
                                  .child('properties')
                                  .child(propId)
                                  .child('media')
                                  .child(filename);
                              await ref.putData(bytes);
                              final url = await ref.getDownloadURL();
                              newUrls.add(url);
                              if (mounted) {
                                setState(() {
                                  _uploadPhotoProgress = (i + 1) / files.length;
                                });
                              }
                            }
                            if (newUrls.isNotEmpty) {
                              await docRef.set({
                                'images': FieldValue.arrayUnion(newUrls),
                                'propertyPhotos': FieldValue.arrayUnion(newUrls),
                              }, SetOptions(merge: true));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Photos uploaded.')));
                              }
                            }
                            if (mounted) {
                              setState(() {
                                _uploadingPhotos = false;
                                _uploadPhotoProgress = 0.0;
                              });
                            }
                          } catch (e) {
                            if (mounted) {
                              setState(() {
                                _uploadingPhotos = false;
                                _uploadPhotoProgress = 0.0;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('Upload failed: $e')));
                            }
                          }
                        },
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Upload Property Photos'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (imageUrls.isNotEmpty)
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: imageUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final url = imageUrls[index];
                    return SizedBox(
                      width: 120,
                      height: 90,
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              url,
                              width: 120,
                              height: 90,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 120,
                                height: 90,
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.broken_image),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => _deletePropertyPhoto(url),
                                child: const Padding(
                                  padding: EdgeInsets.all(4.0),
                                  child: Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              )
            else
              Text('No photos yet. Upload some to make your listing pop.',
                  style: GoogleFonts.poppins(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            Row(children: [
              ElevatedButton(
                  onPressed: () async {
                    try {
                      await docRef.set({
                        'propertyLabel': propertyLabelCtrl.text.trim(),
                        'gcashNumber': gcashCtrl.text.trim(),
                        'mayaNumber': mayaCtrl.text.trim(),
                        'bankDetails': bankDetailsCtrl.text.trim(),
                        'updatedAt': FieldValue.serverTimestamp()
                      }, SetOptions(merge: true));
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Property payment settings saved')));
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
      },
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
      final guestKey = _guestPropertyKey();
      final docRef =
          FirebaseFirestore.instance.collection('properties').doc(guestKey);
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

  Future<void> _deleteStagedHoliday(String key) async {
    setState(() {
      stagedHolidayRates.remove(key);
      if (editingHolidayKey == key) editingHolidayKey = null;
    });

    try {
      final guestKey = _guestPropertyKey();
      if (guestKey.isNotEmpty) {
        final docRef = FirebaseFirestore.instance
            .collection('properties')
            .doc(guestKey);
        await docRef.update({
          'holidayRates.$key': FieldValue.delete(),
          'holidayDates': FieldValue.arrayRemove([key]),
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Holiday removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove holiday: $e')),
        );
      }
    }
  }

  /// Persists current weekday/weekend rate maps to Firestore (prop + slug doc).
  Future<void> _persistStandardRates() async {
    final propId = _propId();
    final guestKey = _guestPropertyKey();
    final weekday = <String, dynamic>{};
    weekdayControllers.forEach((k, c) {
      final v = double.tryParse(c.text.replaceAll(',', '')) ?? 0.0;
      weekday[k] = v;
    });
    final weekend = <String, dynamic>{};
    weekendControllers.forEach((k, c) {
      final v = double.tryParse(c.text.replaceAll(',', '')) ?? 0.0;
      weekend[k] = v;
    });
    final payload = <String, dynamic>{
      'weekdayRates': weekday,
      'weekendRates': weekend,
    };
    try {
      final docRef = FirebaseFirestore.instance
          .collection('properties')
          .doc(propId);
      await docRef.set(payload, SetOptions(merge: true));
      if (guestKey != propId) {
        final slugRef = FirebaseFirestore.instance
            .collection('properties')
            .doc(guestKey);
        await slugRef.set(payload, SetOptions(merge: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save rates: $e')),
        );
      }
    }
  }

  Future<void> _deleteWeekdayRate(String key) async {
    setState(() {
      if (editingWeekdayKey == key) editingWeekdayKey = null;
      final old = weekdayControllers.remove(key);
      old?.dispose();
    });
    await _persistStandardRates();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weekday rate removed')),
      );
    }
  }

  Future<void> _deleteWeekendRate(String key) async {
    setState(() {
      if (editingWeekendKey == key) editingWeekendKey = null;
      final old = weekendControllers.remove(key);
      old?.dispose();
    });
    await _persistStandardRates();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weekend rate removed')),
      );
    }
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
    // Read from current property doc so existing rates (e.g. 57I...) show in form
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
                                                                        () => _deleteWeekdayRate(e.key))
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
                                                                        () => _deleteWeekendRate(e.key))
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
                                    final payload = <String, dynamic>{
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
                                              securityDepositCtrl.text
                                                  .replaceAll(',', '')) ??
                                          0.0,
                                      'addOns': addOns,
                                      'holidayDates': FieldValue.arrayUnion(
                                          stagedHolidayRates.keys.toList()),
                                      ...holidayRateUpdates,
                                    };
                                    await docRef.set(payload, SetOptions(merge: true));
                                    // Also write to slug doc so booking page (which uses slug) sees the same rates
                                    final guestKey = _guestPropertyKey();
                                    if (guestKey != propId) {
                                      final slugRef = FirebaseFirestore.instance
                                          .collection('properties')
                                          .doc(guestKey);
                                      await slugRef.set(payload, SetOptions(merge: true));
                                    }
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
        content = PerformanceDashboard(
          propertyId: _guestPropertyKey(),
          onDateSelected: (selected) {
            setState(() {
              _bookingFilterDate = selected;
              _selectedIndex = 1;
            });
          },
        );
        break;
      case 1:
        content = _liveBookings();
        break;
      case 2:
        content = _propertySettings();
        break;
      case 3:
        content = _themeDecorator();
        break;
      case 4:
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
