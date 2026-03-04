// ignore_for_file: unnecessary_null_comparison
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  // Booking availability: per-date hours already booked (verified)
  final Map<DateTime, int> _dailyBookedHours = {};
  static const int _maxDailyHours = 24;
  bool _availabilityLoaded = false;

  // Gallery state (desktop): which photo is shown as the large image
  int _primaryPhotoIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadExistingBookings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    primaryColor = Theme.of(context).primaryColor;
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  int _hoursFromDurationLabel(String? label) {
    if (label == null) return 0;
    final lower = label.toLowerCase();
    if (lower.contains('overnight')) return 22;
    // Fallback: pull first number
    final match = RegExp(r'(\d+)').firstMatch(lower);
    if (match != null) {
      final v = int.tryParse(match.group(1) ?? '');
      if (v != null) {
        // Treat anything >= 22 as an overnight block
        return v >= 22 ? 22 : v;
      }
    }
    return 0;
  }

  Future<void> _loadExistingBookings() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('propertySlug', isEqualTo: widget.slug)
          .where('paymentStatus', isEqualTo: 'verified')
          .get();
      final Map<DateTime, int> temp = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final durRaw = data['selectedDuration'] ?? data['duration'];
        final String duration =
            durRaw == null ? '' : durRaw.toString().toLowerCase();
        final int durHours = _hoursFromDurationLabel(duration);

        List<DateTime> days = [];
        final rawStay = data['stayDates'];
        if (rawStay is List && rawStay.isNotEmpty) {
          for (final v in rawStay) {
            if (v is Timestamp) {
              days.add(_dateOnly(v.toDate()));
            }
          }
        } else {
          DateTime? _asDate(dynamic v) {
            if (v == null) return null;
            if (v is Timestamp) return v.toDate();
            if (v is DateTime) return v;
            if (v is String) return DateTime.tryParse(v);
            return null;
          }

          final checkIn = _asDate(
              data['checkInDate'] ?? data['checkIn'] ?? data['startDate']);
          final checkOut = _asDate(
              data['checkOutDate'] ?? data['checkOut'] ?? data['endDate']);
          if (checkIn != null && checkOut != null) {
            var cursor = _dateOnly(checkIn);
            final end = _dateOnly(checkOut);
            while (cursor.isBefore(end)) {
              days.add(cursor);
              cursor = cursor.add(const Duration(days: 1));
            }
          }
        }

        // Multi-night (overnight) stays: fully block every date in the range
        if (days.length > 1) {
          for (final day in days) {
            temp[day] = _maxDailyHours;
          }
        } else if (days.length == 1 && durHours > 0) {
          // Single-day duration booking: add hours so remaining hours logic applies
          final day = days.single;
          temp[day] = (temp[day] ?? 0) + durHours;
          if (temp[day]! > _maxDailyHours) temp[day] = _maxDailyHours;
        }
      }
      if (mounted) {
        setState(() {
          _dailyBookedHours
            ..clear()
            ..addAll(temp);
          _availabilityLoaded = true;
        });
      }
    } catch (_) {
      // If this fails, we just skip availability hints
    }
  }

  bool _isDateFullyBooked(DateTime date) {
    final key = _dateOnly(date);
    final hours = _dailyBookedHours[key] ?? 0;
    return hours >= _maxDailyHours;
  }

  Future<bool> _confirmSlotStillAvailable() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('propertySlug', isEqualTo: widget.slug)
          .where('paymentStatus', isEqualTo: 'verified')
          .get();

      final Map<DateTime, int> occupiedHours = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        List<DateTime> days = [];
        final rawStay = data['stayDates'];
        if (rawStay is List && rawStay.isNotEmpty) {
          for (final v in rawStay) {
            if (v is Timestamp) {
              days.add(_dateOnly(v.toDate()));
            }
          }
        } else {
          DateTime? _asDate(dynamic v) {
            if (v == null) return null;
            if (v is Timestamp) return v.toDate();
            if (v is DateTime) return v;
            if (v is String) return DateTime.tryParse(v);
            return null;
          }

          final checkIn = _asDate(
              data['checkInDate'] ?? data['checkIn'] ?? data['startDate']);
          final checkOut = _asDate(
              data['checkOutDate'] ?? data['checkOut'] ?? data['endDate']);
          if (checkIn != null && checkOut != null) {
            var cursor = _dateOnly(checkIn);
            final end = _dateOnly(checkOut);
            while (cursor.isBefore(end)) {
              days.add(cursor);
              cursor = cursor.add(const Duration(days: 1));
            }
          }
        }
        final int durHours =
            _hoursFromDurationLabel(data['selectedDuration']?.toString());
        if (days.length > 1) {
          for (final d in days) {
            occupiedHours[d] = _maxDailyHours;
          }
        } else if (days.length == 1 && durHours > 0) {
          final d = days.single;
          occupiedHours[d] = (occupiedHours[d] ?? 0) + durHours;
          if (occupiedHours[d]! > _maxDailyHours) occupiedHours[d] = _maxDailyHours;
        }
      }

      final List<DateTime> selectedDays = _selectedRangeDates.isNotEmpty
          ? _selectedRangeDates
          : (_selectedDay != null
              ? [_selectedDay!]
              : [_focusedDay]);

      final int newHoursPerDay =
          _hoursFromDurationLabel(selectedDuration ?? '8h');

      for (final d in selectedDays) {
        final key = _dateOnly(d);
        final existing = occupiedHours[key] ?? 0;
        if (newHoursPerDay <= 0) continue;
        if (existing + newHoursPerDay > _maxDailyHours) return false;
      }
      return true;
    } catch (_) {
      // In case of error, do not block booking, but refresh map
      await _loadExistingBookings();
      return true;
    }
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

    final List<String> urls = <String>[];
    String? _asUrl(dynamic v) {
      if (v == null) return null;
      if (v is String) return v.trim();
      if (v is Map) return (v['url'] ?? v['src'])?.toString().trim();
      return v.toString().trim();
    }

    if (raw is List) {
      for (final item in raw) {
        final u = _asUrl(item);
        if (u != null && u.isNotEmpty && (u.startsWith('http://') || u.startsWith('https://'))) {
          urls.add(u);
        }
      }
    } else if (raw is Map) {
      raw.forEach((_, v) {
        final u = _asUrl(v);
        if (u != null && u.isNotEmpty && (u.startsWith('http://') || u.startsWith('https://'))) {
          urls.add(u);
        }
      });
    }

    return urls;
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
    final Map<String, double> base = _isWeekend(date)
        ? Map<String, double>.from(weekendRates)
        : Map<String, double>.from(weekdayRates);

    // Filter out durations that don't fit remaining daily hours
    if (_availabilityLoaded) {
      final usedHours = _dailyBookedHours[_dateOnly(date)] ?? 0;
      final remaining = _maxDailyHours - usedHours;
      if (remaining <= 0) {
        return <String, double>{};
      }
      base.removeWhere((label, _) {
        final h = _hoursFromDurationLabel(label);
        return h <= 0 || h > remaining;
      });
    }

    return base;
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

    // Only show add-ons that have a price > 0 (set in Pricing Manager)
    final addonEntriesWithPrice = <MapEntry<int, Map<String, dynamic>>>[];
    for (int i = 0; i < addons.length; i++) {
      final a = addons[i];
      double p = 0.0;
      if (a['price'] is num) p = (a['price'] as num).toDouble();
      else p = double.tryParse(a['price']?.toString() ?? '') ?? 0.0;
      if (p > 0) addonEntriesWithPrice.add(MapEntry(i, a));
    }
    final addonsWidget = addonEntriesWithPrice.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              ...addonEntriesWithPrice.map((e) {
                final i = e.key;
                final a = e.value;
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
              }),
            ],
          );

    // compute extra heads for display
    final int displayExtraHeads = math.max(0, totalPax - maxBaseGuests);
    final String headsLabel = displayExtraHeads == 1 ? 'head' : 'heads';

    // Base rate display: per-night first for multi-night, then total (no weekday/weekend label)
    final bool isMultiNight = lastStayNights > 1;
    final List<Widget> baseRateLines = [];
    if (isMultiNight) {
      baseRateLines.add(_buildPriceLine(
          'Base Rate (per night)',
          '₱${lastBaseStayPrice.toStringAsFixed(2)}'));
      baseRateLines.add(_buildPriceLine(
          'Base Rate × $lastStayNights Nights',
          '₱${baseTotal.toStringAsFixed(2)}'));
    } else {
      baseRateLines.add(_buildPriceLine(
          lastStayNights == 1 ? 'Base Rate (1 Night)' : 'Base Rate',
          '₱${baseTotal.toStringAsFixed(2)}'));
    }

    final content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // selectors moved into the card
          _buildSelectors(),
          addonsWidget,
          const SizedBox(height: 12),

          // Invoice-style line items
          ...baseRateLines,
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

          if (baseTotal <= 0 && weekdayRates.isEmpty && weekendRates.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Rates not set for this property yet.',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
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
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
            ),
            onPressed: (baseTotal <= 0 || grandTotal <= 0)
                ? null
                : () async {
                    final isAvailable =
                        await _confirmSlotStillAvailable();
                    if (!isAvailable) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Sorry, this slot was just taken!',
                            style: GoogleFonts.poppins(
                                color: Colors.white),
                          ),
                          backgroundColor: Colors.red.shade600,
                        ),
                      );
                      await _loadExistingBookings();
                      return;
                    }

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
            child: Text(
              'Reserve Now',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
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
    if (photos.isEmpty) {
      return Container(
        height: isMobile ? 250 : 400,
        color: Colors.grey.shade200,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'No photos for this property yet.',
                style: GoogleFonts.poppins(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 4),
              Text(
                'On web, if you uploaded photos and see broken images,\nconfigure Storage CORS (see STORAGE_CORS_SETUP.md).',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

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
    final int primaryIndex = _primaryPhotoIndex.clamp(0, photos.length - 1);
    final String primary = photos[primaryIndex];
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
              itemCount: photos.length,
              itemBuilder: (c, i) {
                final thumbUrl = photos[i];
                final bool isSelected = i == primaryIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _primaryPhotoIndex = i;
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? primaryColor
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          thumbUrl,
                          width: 120,
                          height: 80,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2)),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                                child: Icon(Icons.broken_image,
                                    color: Colors.red)),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
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
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.slug)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
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
        final snapData = snapshot.data!.data() ?? <String, dynamic>{};
        propertyData = snapData;
        _applyPricingFromData(snapData);

        final rawLabel = (snapData['propertyLabel'] ?? snapData['name'] ?? widget.slug)?.toString().trim() ?? '';
        final String displayName = rawLabel.isNotEmpty
            ? rawLabel
            : (widget.slug.isNotEmpty ? widget.slug[0].toUpperCase() + widget.slug.substring(1) : widget.slug);
        final List<String> photos = _extractPhotoUrls(snapData);

        final isMobile = MediaQuery.of(context).size.width < 900;
        final isDesktop = !isMobile;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Book — $displayName',
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
                            Text(displayName,
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
                                  if (_availabilityLoaded &&
                                      active.isEmpty &&
                                      (_dailyBookedHours[_dateOnly(
                                                  selectedDay)] ??
                                              0) >
                                          0) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: Text(
                                        'This date is fully booked. Please choose another date.',
                                        style: GoogleFonts.poppins(
                                            color: Colors.white),
                                      ),
                                      backgroundColor: Colors.red.shade600,
                                    ));
                                    return;
                                  }
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
                                      final d = start.add(Duration(days: i));
                                      if (_availabilityLoaded &&
                                          _isDateFullyBooked(d)) {
                                        continue;
                                      }
                                      _selectedRangeDates.add(d);
                                    }
                                  }
                                });
                                _recalculate();
                              },
                              enabledDayPredicate: (d) {
                                final isPast = d.isBefore(DateTime.now()
                                    .subtract(const Duration(days: 1)));
                                if (isPast) return false;
                                if (!_availabilityLoaded) return true;
                                final active = _getApplicableRateMap(d);
                                // fully booked when there are booked hours but no durations left
                                if ((_dailyBookedHours[_dateOnly(d)] ?? 0) > 0 &&
                                    active.isEmpty) {
                                  return false;
                                }
                                return true;
                              },
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
                      Text(displayName,
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
                            if (_availabilityLoaded &&
                                active.isEmpty &&
                                (_dailyBookedHours[_dateOnly(
                                            selectedDay)] ??
                                        0) >
                                    0) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text(
                                  'This date is fully booked. Please choose another date.',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white),
                                ),
                                backgroundColor: Colors.red.shade600,
                              ));
                              return;
                            }
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
                                final d = start.add(Duration(days: i));
                                if (_availabilityLoaded &&
                                    _isDateFullyBooked(d)) {
                                  continue;
                                }
                                _selectedRangeDates.add(d);
                              }
                            }
                          });
                          _recalculate();
                        },
                        enabledDayPredicate: (d) {
                          final isPast = d.isBefore(DateTime.now()
                              .subtract(const Duration(days: 1)));
                          if (isPast) return false;
                          if (!_availabilityLoaded) return true;
                          final active = _getApplicableRateMap(d);
                          if ((_dailyBookedHours[_dateOnly(d)] ?? 0) > 0 &&
                              active.isEmpty) {
                            return false;
                          }
                          return true;
                        },
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
