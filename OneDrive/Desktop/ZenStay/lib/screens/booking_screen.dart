// ignore_for_file: unnecessary_null_comparison
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

import 'checkout_screen.dart';

class BookingScreen extends StatefulWidget {
  final String slug;
  const BookingScreen({Key? key, required this.slug}) : super(key: key);

  @override
  _BookingScreenState createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  Map<String, dynamic>? propertyData;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  List<DateTime> _selectedRangeDates = [];

  // Pricing maps hydrated from the property document
  Map<String, double> weekdayRates = {}; // duration -> price
  Map<String, double> weekendRates = {}; // duration -> price
  Map<String, Map<String, double>> holidayRates =
      {}; // dateString -> { duration -> price }
  Map<String, double> holidayDefaults = {}; // default holiday duration -> price
  Map<String, double> _currentActiveMap = {}; // currently active rate map for UI
  List<String> holidayDates = [];
  String? selectedDuration;
  int totalPax = 1;
  int maxBaseGuests = 1;
  double extraPaxFee = 0.0;

  late Color primaryColor;

  double grandTotal = 0.0;
  String priceBreakdownText = '';
  String appliedRateLabel = ''; // e.g. 'Weekday Rate applied'

  double lastBaseStayPrice = 0.0;
  double lastTotalExtraPaxFee = 0.0;
  double lastSecurityDeposit = 0.0;
  int lastStayNights = 1;
  double lastCleaningFee = 0.0;
  List<Map<String, dynamic>> addons = [];
  Set<int> selectedAddonIndexes = {};
  double lastAddonsTotal = 0.0;

  // Storage-backed images
  List<String> storagePhotos = [];

  @override
  void initState() {
    super.initState();
    _fetchLiveRates();
    _loadProperty();
    _loadStorageImages();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    primaryColor = Theme.of(context).primaryColor;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  List<String> _extractPhotoUrls(Map<String, dynamic>? data) {
    if (data == null) return <String>[];
    // Try several common keys so we stay resilient to schema drift
    final dynamic raw = data['propertyPhotos'] ??
        data['photos'] ??
        data['imageUrls'] ??
        data['images'] ??
        data['gallery'];

    debugPrint('DEBUG photos raw type: ${raw.runtimeType}');

    final List<String> urls = <String>[];
    if (raw is List) {
      for (final item in raw) {
        if (item == null) continue;
        if (item is String) {
          if (item.trim().isNotEmpty) urls.add(item.trim());
        } else if (item is Map) {
          final u = item['url']?.toString() ?? item['src']?.toString();
          if (u != null && u.trim().isNotEmpty) urls.add(u.trim());
        }
      }
    } else if (raw is Map) {
      // Map of id -> url
      raw.forEach((_, v) {
        final u = v?.toString();
        if (u != null && u.trim().isNotEmpty) urls.add(u.trim());
      });
    }

    debugPrint('DEBUG photo URLs extracted: $urls');
    return urls;
  }

  Future<void> _loadStorageImages() async {
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('properties')
          .child(widget.slug)
          .child('media');
      final result = await ref.listAll();
      final urls = <String>[];
      for (final item in result.items) {
        try {
          final url = await item.getDownloadURL();
          if (url.isNotEmpty) urls.add(url);
        } catch (e) {
          debugPrint('Error getting download URL for ${item.fullPath}: $e');
        }
      }
      debugPrint('DEBUG storage photo URLs: $urls');
      if (mounted) {
        setState(() {
          storagePhotos = urls;
        });
      }
    } catch (e) {
      debugPrint('Error listing storage images: $e');
    }
  }

  void _applyPricingFromData(Map<String, dynamic> data) {
    // Base weekday / weekend maps
    final rawWeekday = data['weekdayRates'];
    final rawWeekend = data['weekendRates'];
    final Map<String, double> weekday = {};
    final Map<String, double> weekend = {};
    if (rawWeekday is Map) {
      rawWeekday.forEach((k, v) {
        final key = k.toString();
        final val = _toDouble(v);
        if (val > 0) weekday[key] = val;
      });
    }
    if (rawWeekend is Map) {
      rawWeekend.forEach((k, v) {
        final key = k.toString();
        final val = _toDouble(v);
        if (val > 0) weekend[key] = val;
      });
    }

    // Holiday maps: { dateString: { name, rates: { duration: price } } }
    final Map<String, Map<String, double>> holiday = {};
    final rawHoliday = data['holidayRates'];
    if (rawHoliday is Map) {
      rawHoliday.forEach((dateKey, entry) {
        if (entry is Map) {
          final inner = entry['rates'] is Map ? entry['rates'] : entry;
          if (inner is Map) {
            final Map<String, double> m = {};
            inner.forEach((dur, price) {
              final key = dur.toString();
              final val = _toDouble(price);
              if (val > 0) m[key] = val;
            });
            if (m.isNotEmpty) {
              holiday[dateKey.toString()] = m;
            }
          }
        }
      });
    }

    final Map<String, double> holidayDefault = {};
    final rawDefault = data['holidayRatesByDuration'];
    if (rawDefault is Map) {
      rawDefault.forEach((k, v) {
        final key = k.toString();
        final val = _toDouble(v);
        if (val > 0) holidayDefault[key] = val;
      });
    }

    weekdayRates = weekday;
    weekendRates = weekend;
    holidayRates = holiday;
    holidayDefaults = holidayDefault;

    extraPaxFee =
        double.tryParse(data['extraPaxFee']?.toString() ?? '0') ?? 0.0;
    // Support both maxBaseGuests and baseGuestsIncluded from Firestore
    final baseGuestsRaw =
        data['maxBaseGuests'] ?? data['baseGuestsIncluded'] ?? '1';
    maxBaseGuests = int.tryParse(baseGuestsRaw.toString()) ?? 1;

    // load addons if present (owner UI may use 'addons' or 'addOns')
    final rawAddons = data['addons'] ?? data['addOns'] ?? [];
    if (rawAddons is List) {
      addons = rawAddons
          .map<Map<String, dynamic>>((e) =>
              e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
          .toList();
    } else if (rawAddons is Map) {
      // OwnerDashboard saves addOns as a map; normalize to a list
      addons = rawAddons.entries
          .map<Map<String, dynamic>>((e) => {
                'name': e.key.toString(),
                'price': _toDouble(e.value),
              })
          .toList();
    } else {
      addons = <Map<String, dynamic>>[];
    }

    holidayDates = (data['holidayDates'] is List)
        ? List<String>.from(data['holidayDates'])
        : <String>[];

    print('PRICING DATA LOADED: $weekdayRates');

    // Default duration for single-day bookings
    selectedDuration = selectedDuration ??
        (weekdayRates.keys.isNotEmpty
            ? weekdayRates.keys.first
            : (weekendRates.keys.isNotEmpty ? weekendRates.keys.first : '8h'));

    // Initialize active map so the dropdown has data even before a tap
    if (_currentActiveMap.isEmpty) {
      final today = _focusedDay;
      _currentActiveMap = _isWeekend(today)
          ? (weekendRates.isNotEmpty ? weekendRates : weekdayRates)
          : (weekdayRates.isNotEmpty ? weekdayRates : weekendRates);
    }
  }

  Future<void> _loadProperty() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('properties')
          .where('slug', isEqualTo: widget.slug)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        final data =
            query.docs.first.data() as Map<String, dynamic>? ?? <String, dynamic>{};
        setState(() {
          propertyData = data;
          _applyPricingFromData(data);
        });
        _recalculate();
      }
    } catch (_) {}
  }

  Future<void> _fetchLiveRates() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('properties')
          .where('slug', isEqualTo: widget.slug)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        final data =
            query.docs.first.data() as Map<String, dynamic>? ?? <String, dynamic>{};
        debugPrint(
            '[fetchLiveRates] weekdayRates keys: ${(data['weekdayRates'] as Map?)?.keys.toList()}');
        debugPrint(
            '[fetchLiveRates] weekendRates keys: ${(data['weekendRates'] as Map?)?.keys.toList()}');
        debugPrint(
            '[fetchLiveRates] holidayRates dates: ${(data['holidayRates'] as Map?)?.keys.toList()}');
        setState(() {
          _applyPricingFromData(data);
        });
        _recalculate();
      }
    } catch (e) {
      debugPrint('Error fetching live rates: $e');
    }
  }

  // removed unused helper _parsePrice

  bool _isWeekend(DateTime date) {
    return date.weekday == DateTime.friday ||
        date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;
  }

  String _getOvernightKey(Map<String, double> rates) {
    if (rates.isEmpty) return '';
    for (final k in rates.keys) {
      final lower = k.toString().toLowerCase();
      if (lower.contains('22') ||
          lower.contains('overnight') ||
          lower.contains('24')) return k.toString();
    }
    return rates.keys.last.toString();
  }

  Map<String, double> _getApplicableRateMap(DateTime date) {
    final String dateString = DateFormat('yyyy-MM-dd').format(date);
    if (holidayRates.containsKey(dateString)) {
      return holidayRates[dateString]!;
    }
    if (holidayDates.contains(dateString) && holidayDefaults.isNotEmpty) {
      return Map<String, double>.from(holidayDefaults);
    }
    return _isWeekend(date)
        ? Map<String, double>.from(weekendRates)
        : Map<String, double>.from(weekdayRates);
  }

  void _recalculate() {
    if (propertyData == null) return;
    debugPrint(
        '[recalc] selectedDay=$_selectedDay rangeStart=$_rangeStart rangeEnd=$_rangeEnd selectedRangeDates=${_selectedRangeDates.length} selectedDuration=$selectedDuration');

    // clear stale list state
    if (_rangeStart == null &&
        _rangeEnd == null &&
        _selectedRangeDates.isNotEmpty) {
      _selectedRangeDates = [];
    }

    if (_selectedDay != null) {
      _rangeStart = null;
      _rangeEnd = null;
      _selectedRangeDates = [];
    }

    // Determine whether this is a single-day or multi-night stay
    int nights = 0;
    DateTime pricingAnchor = _focusedDay;
    List<DateTime> nightDates = [];

    if (_selectedDay != null) {
      nights = 0;
      pricingAnchor = _selectedDay!;
      nightDates = [pricingAnchor];
    } else if (_rangeStart != null && _rangeEnd != null) {
      nights = _rangeEnd!.difference(_rangeStart!).inDays;
      if (nights < 1) nights = 1;
      pricingAnchor = _rangeStart!;
      nightDates = List.generate(
          nights, (i) => _rangeStart!.add(Duration(days: i)));
    } else if (_selectedRangeDates.isNotEmpty) {
      nights = _selectedRangeDates.length;
      if (nights < 1) nights = 1;
      pricingAnchor = _selectedRangeDates.first;
      nightDates = List.from(_selectedRangeDates);
    } else {
      nights = 0;
      pricingAnchor = _focusedDay;
      nightDates = [pricingAnchor];
    }

    final bool isMultiNight = nights > 0;

    double perNightRate = 0.0;
    String rateContextLabel = '';

    String _rateContextForDate(DateTime d) {
      final dateString = DateFormat('yyyy-MM-dd').format(d);
      if (holidayRates.containsKey(dateString) ||
          holidayDates.contains(dateString)) {
        return 'Holiday Rate applied';
      }
      return _isWeekend(d) ? 'Weekend Rate applied' : 'Weekday Rate applied';
    }

    if (!isMultiNight) {
      // Single-day: use the selected duration from the active/applicable map
      final map = _currentActiveMap.isNotEmpty
          ? _currentActiveMap
          : _getApplicableRateMap(pricingAnchor);
      _currentActiveMap = map;
      final durations = map.keys.toList()..sort();
      String effectiveDuration = selectedDuration ??
          (durations.isNotEmpty ? durations.first : '8h');
      if (!map.containsKey(effectiveDuration) && durations.isNotEmpty) {
        effectiveDuration = durations.first;
      }
      selectedDuration = effectiveDuration;
      final raw = map[effectiveDuration];
      perNightRate = raw != null
          ? double.tryParse(raw.toString()) ?? 0.0
          : 0.0;
      if (perNightRate == 0.0 && map.isNotEmpty) {
        final isWknd = _isWeekend(pricingAnchor);
        debugPrint(
            'DEBUG: No rate found for $effectiveDuration in ${isWknd ? 'Weekend' : 'Weekday'} map.');
      }
      rateContextLabel = _rateContextForDate(pricingAnchor);
      lastStayNights = 1;
    } else {
      // Multi-night: highest overnight/long-stay rate across all nights
      double highestRate = 0.0;
      String bestLabel = '';
      for (final d in nightDates) {
        final map = _getApplicableRateMap(d);
        if (map.isEmpty) continue;
        String overnightKey =
            map.containsKey('22h') ? '22h' : _getOvernightKey(map);
        double candidate = map[overnightKey] ?? 0.0;
        if (candidate <= 0 && map.isNotEmpty) {
          candidate = map.values.reduce(
              (a, b) => a > b ? a : b); // fallback: highest duration price
        }
        if (candidate > highestRate) {
          highestRate = candidate;
          bestLabel = _rateContextForDate(d);
        }
      }
      perNightRate = highestRate;
      rateContextLabel = bestLabel.isNotEmpty ? bestLabel : 'Rate applied';
      // lock UI to overnight for multi-night selections
      selectedDuration = '22h';
      lastStayNights = nights;
    }

    lastBaseStayPrice = perNightRate;
    final int effectiveNights = isMultiNight ? nights : 1;
    final baseStayTotal = perNightRate * effectiveNights;
    if (baseStayTotal == 0.0) {
      debugPrint(
          'DEBUG: No rate found for $selectedDuration in map.');
    }

    final extraHeads = math.max(0, totalPax - maxBaseGuests);
    lastTotalExtraPaxFee = extraPaxFee * extraHeads * effectiveNights;

    // addons total
    double addonsTotal = 0.0;
    for (final idx in selectedAddonIndexes) {
      if (idx >= 0 && idx < addons.length) {
        final a = addons[idx];
        double p = 0.0;
        final priceVal = a['price'];
        if (priceVal is num)
          p = priceVal.toDouble();
        else
          p = double.tryParse(priceVal?.toString() ?? '') ?? 0.0;
        addonsTotal += p;
      }
    }
    lastAddonsTotal = addonsTotal;

    lastSecurityDeposit =
        double.tryParse(propertyData?['securityDeposit']?.toString() ?? '0') ??
            0.0;
    final cleaning =
        double.tryParse(propertyData?['cleaningFee']?.toString() ?? '0') ?? 0.0;
    lastCleaningFee = cleaning;

    grandTotal = baseStayTotal +
        lastTotalExtraPaxFee +
        lastSecurityDeposit +
        cleaning +
        lastAddonsTotal;

    appliedRateLabel = rateContextLabel;

    priceBreakdownText =
        '$rateContextLabel\n₱${perNightRate.toStringAsFixed(2)} x $effectiveNights night${effectiveNights > 1 ? 's' : ''} = ₱${baseStayTotal.toStringAsFixed(2)}\n';
    priceBreakdownText +=
        'Base guests included: $maxBaseGuests\n';
    if (extraHeads > 0) {
      priceBreakdownText +=
          'Extra pax: ₱${extraPaxFee.toStringAsFixed(2)} x $extraHeads x $effectiveNights night${effectiveNights > 1 ? 's' : ''} = ₱${lastTotalExtraPaxFee.toStringAsFixed(2)}\n';
    } else {
      priceBreakdownText += 'Extra pax: ₱0.00\n';
    }
    if (cleaning > 0)
      priceBreakdownText += 'Cleaning: ₱${cleaning.toStringAsFixed(2)}\n';
    if (lastSecurityDeposit > 0)
      priceBreakdownText +=
          'Deposit: ₱${lastSecurityDeposit.toStringAsFixed(2)}\n';

    debugPrint(
        '[recalc-result] grandTotal=$grandTotal breakdown=$priceBreakdownText');
    setState(() {});
  }

  Widget _buildSelectors() {
    final bool isMultiNight = (_rangeStart != null &&
            _rangeEnd != null &&
            _rangeEnd!.difference(_rangeStart!).inDays >= 1) ||
        (_selectedRangeDates.length >= 2);

    final DateTime dateForLookup = _selectedDay ?? _focusedDay;
    // Prefer the active map if set; otherwise compute from classifier
    final Map<String, double> mapForUi =
        _currentActiveMap.isNotEmpty ? _currentActiveMap : _getApplicableRateMap(dateForLookup);
    final available = mapForUi.keys.toList()..sort();
    final List<String> fallback = weekdayRates.keys.toList()..sort();

    String? safeVal = selectedDuration;
    if (safeVal == null || (!available.contains(safeVal) && available.isNotEmpty)) {
      safeVal = available.isNotEmpty
          ? available.first
          : (fallback.isNotEmpty ? fallback.first : '8h');
    }

    if (!isMultiNight) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButton<String>(
          value: safeVal,
          hint: const Text('Select Duration'),
          items: available.isNotEmpty
              ? available
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList()
              : fallback
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
          onChanged: (v) {
            setState(() => selectedDuration = v);
            _recalculate();
          },
        ),
        const SizedBox(height: 8),
        DropdownButton<int>(
          value: totalPax,
          items: List.generate(6, (i) => i + 1)
              .map((g) => DropdownMenuItem(
                  value: g, child: Text('$g Guest${g > 1 ? 's' : ''}')))
              .toList(),
          onChanged: (v) {
            setState(() => totalPax = v ?? 1);
            _recalculate();
          },
        ),
      ]);
    }

    // Multi-night: hide duration dropdown and show overnight label
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Stay: Overnight (multi-night stay)',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      DropdownButton<int>(
        value: totalPax,
        items: List.generate(6, (i) => i + 1)
            .map((g) => DropdownMenuItem(
                value: g, child: Text('$g Guest${g > 1 ? 's' : ''}')))
            .toList(),
        onChanged: (v) {
          setState(() => totalPax = v ?? 1);
          _recalculate();
        },
      ),
    ]);
  }

  Widget _buildBookingCard({bool isDesktop = false}) {
    final baseTotal = lastBaseStayPrice * lastStayNights;

    final addonsWidget = addons.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              ...List.generate(addons.length, (i) {
                final a = addons[i];
                final title =
                    a['name']?.toString() ?? a['label']?.toString() ?? 'Addon';
                double price = 0.0;
                if (a['price'] is num)
                  price = (a['price'] as num).toDouble();
                else
                  price = double.tryParse(a['price']?.toString() ?? '') ?? 0.0;
                return CheckboxListTile(
                  value: selectedAddonIndexes.contains(i),
                  onChanged: (v) {
                    setState(() {
                      if (v == true)
                        selectedAddonIndexes.add(i);
                      else
                        selectedAddonIndexes.remove(i);
                      _recalculate();
                    });
                  },
                  title: Text(title, style: GoogleFonts.poppins(fontSize: 14)),
                  secondary: Text('₱${price.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(fontSize: 13)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                );
              })
            ],
          );

    // compute an explicit night label (use nights when range selected, otherwise show selected duration)
    int _computedNights = 0;
    if (_rangeStart != null && _rangeEnd != null) {
      _computedNights = _rangeEnd!.difference(_rangeStart!).inDays;
    } else if (_selectedRangeDates.isNotEmpty) {
      _computedNights = _selectedRangeDates.length;
    } else {
      _computedNights = lastStayNights;
    }
    final String stayLabel = _computedNights > 0
        ? '$_computedNights Night${_computedNights > 1 ? 's' : ''}'
        : (selectedDuration ?? '${lastStayNights} night');

    // compute extra heads for display
    final int displayExtraHeads = math.max(0, totalPax - maxBaseGuests);
    final String headsLabel = displayExtraHeads == 1 ? 'head' : 'heads';

    final content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // selectors moved into the card
          _buildSelectors(),
          addonsWidget,
          const SizedBox(height: 12),

          // Invoice-style line items
          _buildPriceLine(
              'Base Rate ($stayLabel${appliedRateLabel.isNotEmpty ? ' · $appliedRateLabel' : ''})',
              '₱${baseTotal.toStringAsFixed(2)}'),
          _buildPriceLine(
              'Base Guests Included', '$maxBaseGuests Guest${maxBaseGuests == 1 ? '' : 's'}'),
          if (lastCleaningFee > 0)
            _buildPriceLine(
                'Cleaning', '₱${lastCleaningFee.toStringAsFixed(2)}'),
          if (lastAddonsTotal > 0)
            _buildPriceLine(
                'Add-ons', '₱${lastAddonsTotal.toStringAsFixed(2)}'),
          _buildPriceLine(
              'Extra Guest Fee${displayExtraHeads > 0 ? ' ($displayExtraHeads $headsLabel x ${lastStayNights} night${lastStayNights > 1 ? 's' : ''})' : ''}',
              '₱${lastTotalExtraPaxFee.toStringAsFixed(2)}'),
          _buildPriceLine('Security Deposit (Refundable)',
              '₱${lastSecurityDeposit.toStringAsFixed(2)}'),
          const Divider(height: 32, thickness: 1),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text('₱${grandTotal.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryColor)),
            ],
          ),
          const SizedBox(height: 12),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            onPressed: baseTotal <= 0
                ? null
                : () {
                    final stayDates = _selectedRangeDates.isNotEmpty
                        ? _selectedRangeDates
                        : (_selectedDay != null
                            ? [_selectedDay!]
                            : [_focusedDay]);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (c) => CheckoutScreen(
                              total: grandTotal,
                              paymentMethods: [],
                              slug: widget.slug,
                              checkInDate: _selectedDay ?? _focusedDay,
                              selectedDuration: selectedDuration ?? '8h',
                              totalPax: totalPax,
                              stayDates: stayDates,
                              baseStayPrice: lastBaseStayPrice,
                              totalExtraPaxFee: lastTotalExtraPaxFee,
                              securityDeposit: lastSecurityDeposit,
                            )));
                  },
            child: Text('Reserve Now',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          ),
        ]);

    if (isDesktop) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(padding: const EdgeInsets.all(24.0), child: content),
      );
    }

    return content;
  }

  Widget _buildGallery(List<String> photos, bool isMobile) {
    if (photos.isEmpty)
      return Container(
          height: isMobile ? 250 : 400, color: Colors.grey.shade200);

    if (isMobile) {
      return SizedBox(
        height: 250,
        child: PageView.builder(
          itemCount: photos.length,
          itemBuilder: (c, i) => Image.network(
            photos[i],
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                color: Colors.grey.shade200,
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            },
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey.shade200,
              child: const Center(
                  child: Icon(Icons.broken_image, color: Colors.red, size: 40)),
            ),
          ),
        ),
      );
    }

    // Desktop: large image + thumbnails
    final primary = photos.first;
    final thumbs = photos.length > 1 ? photos.sublist(1) : <String>[];
    return SizedBox(
      height: 400,
      child: Column(
        children: [
          Expanded(
              child: Image.network(
            primary,
            fit: BoxFit.cover,
            width: double.infinity,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                color: Colors.grey.shade200,
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            },
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey.shade200,
              child: const Center(
                  child: Icon(Icons.broken_image, color: Colors.red, size: 40)),
            ),
          )),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: thumbs.length,
              itemBuilder: (c, i) => Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Image.network(
                  thumbs[i],
                  width: 120,
                  height: 80,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.grey.shade200,
                    child: const Center(
                        child:
                            Icon(Icons.broken_image, color: Colors.red)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey[700])),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> photos = storagePhotos.isNotEmpty
        ? storagePhotos
        : _extractPhotoUrls(propertyData ?? <String, dynamic>{});

    final isMobile = MediaQuery.of(context).size.width < 900;
    final isDesktop = !isMobile;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('properties')
          .where('slug', isEqualTo: widget.slug)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                'Book — ${widget.slug.isNotEmpty ? widget.slug[0].toUpperCase() + widget.slug.substring(1) : widget.slug}',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final snapData = snapshot.data!.docs.first.data();
        propertyData = snapData;
        _applyPricingFromData(snapData);

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Book — ${widget.slug.isNotEmpty ? widget.slug[0].toUpperCase() + widget.slug.substring(1) : widget.slug}',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: main content
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildGallery(photos, false),
                            const SizedBox(height: 12),
                            Text(widget.slug.toUpperCase(),
                                style: GoogleFonts.poppins(
                                    fontSize: 22, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            Text(propertyData?['description'] ?? '',
                                style: GoogleFonts.poppins(
                                    color: Colors.grey[800], fontSize: 14)),
                            const SizedBox(height: 16),
                            TableCalendar(
                              firstDay: DateTime.now(),
                              lastDay:
                                  DateTime.now().add(const Duration(days: 365)),
                              focusedDay: _focusedDay,
                              rangeSelectionMode:
                                  RangeSelectionMode.toggledOn,
                              rangeStartDay: _rangeStart,
                              rangeEndDay: _rangeEnd,
                              selectedDayPredicate: (day) =>
                                  isSameDay(_selectedDay, day),
                              onDaySelected: (selectedDay, focusedDay) {
                                if (!isSameDay(_selectedDay, selectedDay)) {
                                  final active =
                                      _getApplicableRateMap(selectedDay);
                                  final durations =
                                      active.keys.toList()..sort();
                                  setState(() {
                                    _selectedDay = selectedDay;
                                    _focusedDay = focusedDay;
                                    _rangeStart = null;
                                    _rangeEnd = null;
                                    _selectedRangeDates = [];
                                    _currentActiveMap = active;
                                    if (_currentActiveMap.isNotEmpty) {
                                      selectedDuration = durations.isNotEmpty
                                          ? durations.first
                                          : selectedDuration;
                                    }
                                  });
                                  _recalculate();
                                }
                              },
                              onRangeSelected: (start, end, focusedDay) {
                                setState(() {
                                  _selectedDay = null;
                                  _focusedDay = focusedDay;
                                  _rangeStart = start;
                                  _rangeEnd = end;
                                  _selectedRangeDates = [];
                                  if (start != null && end != null) {
                                    final diff =
                                        end.difference(start).inDays;
                                    for (int i = 0; i < diff; i++) {
                                      _selectedRangeDates
                                          .add(start.add(Duration(days: i)));
                                    }
                                  }
                                });
                                _recalculate();
                              },
                              enabledDayPredicate: (d) => !d.isBefore(
                                  DateTime.now()
                                      .subtract(const Duration(days: 1))),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Right: booking card
                    SizedBox(
                      width: 360,
                      child: _buildBookingCard(isDesktop: true),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildGallery(photos, true),
                      const SizedBox(height: 12),
                      Text(widget.slug.toUpperCase(),
                          style: GoogleFonts.poppins(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(propertyData?['description'] ?? '',
                          style: GoogleFonts.poppins(color: Colors.grey[800])),
                      const SizedBox(height: 16),
                      TableCalendar(
                        firstDay: DateTime.now(),
                        lastDay:
                            DateTime.now().add(const Duration(days: 365)),
                        focusedDay: _focusedDay,
                        rangeSelectionMode: RangeSelectionMode.toggledOn,
                        rangeStartDay: _rangeStart,
                        rangeEndDay: _rangeEnd,
                        selectedDayPredicate: (day) =>
                            isSameDay(_selectedDay, day),
                        onDaySelected: (selectedDay, focusedDay) {
                          if (!isSameDay(_selectedDay, selectedDay)) {
                            final active =
                                _getApplicableRateMap(selectedDay);
                            final durations = active.keys.toList()..sort();
                            setState(() {
                              _selectedDay = selectedDay;
                              _focusedDay = focusedDay;
                              _rangeStart = null;
                              _rangeEnd = null;
                              _selectedRangeDates = [];
                              _currentActiveMap = active;
                              if (_currentActiveMap.isNotEmpty) {
                                selectedDuration = durations.isNotEmpty
                                    ? durations.first
                                    : selectedDuration;
                              }
                            });
                            _recalculate();
                          }
                        },
                        onRangeSelected: (start, end, focusedDay) {
                          setState(() {
                            _selectedDay = null;
                            _focusedDay = focusedDay;
                            _rangeStart = start;
                            _rangeEnd = end;
                            _selectedRangeDates = [];
                            if (start != null && end != null) {
                              final diff = end.difference(start).inDays;
                              for (int i = 0; i < diff; i++) {
                                _selectedRangeDates
                                    .add(start.add(Duration(days: i)));
                              }
                            }
                          });
                          _recalculate();
                        },
                        enabledDayPredicate: (d) => !d.isBefore(
                            DateTime.now().subtract(const Duration(days: 1))),
                      ),
                      const SizedBox(height: 24),
                      Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: _buildBookingCard())),
                      const SizedBox(height: 32),
                      const SizedBox(height: 40),
                      Center(
                          child: Text('ZenStay Powered By Zenthora',
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: Colors.grey.shade500))),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
            ),
          ),
          bottomNavigationBar: null,
        );
      },
    );
  }
}
