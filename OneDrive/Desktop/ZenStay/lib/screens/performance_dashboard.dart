import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';

class PerformanceDashboard extends StatefulWidget {
  final String propertyId; // slug / document id
  final ValueChanged<DateTime?>? onDateSelected;

  const PerformanceDashboard({
    Key? key,
    required this.propertyId,
    this.onDateSelected,
  }) : super(key: key);

  @override
  State<PerformanceDashboard> createState() => _PerformanceDashboardState();
}

class _PerformanceDashboardState extends State<PerformanceDashboard> {
  final TextEditingController _expenseDescCtrl = TextEditingController();
  final TextEditingController _expenseAmountCtrl = TextEditingController();
  DateTime _expenseDate = DateTime.now();
  bool _savingExpense = false;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void dispose() {
    _expenseDescCtrl.dispose();
    _expenseAmountCtrl.dispose();
    super.dispose();
  }

  DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  /// Normalize to midnight (12:00:00 AM) to avoid off-by-one-day errors.
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _normalizeStatus(dynamic raw) {
    final s = (raw ?? '').toString().toLowerCase().trim();
    if (s.contains('verify')) return 'verified';
    if (s.contains('reject')) return 'rejected';
    if (s.contains('pending')) return 'pending';
    if (s.isEmpty) return 'pending';
    return s;
  }

  int _calcNights(Map<String, dynamic> booking) {
    final checkIn = _asDate(
        booking['checkInDate'] ?? booking['checkIn'] ?? booking['startDate']);
    final checkOut = _asDate(booking['checkOutDate'] ??
        booking['checkOut'] ??
        booking['endDate']);
    if (checkIn != null && checkOut != null) {
      final n = checkOut.difference(checkIn).inDays;
      if (n > 0) return n;
    }
    final rawStayDates = booking['stayDates'];
    if (rawStayDates is List && rawStayDates.isNotEmpty) {
      return rawStayDates.length;
    }
    return 0;
  }

  Future<void> _pickExpenseDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() => _expenseDate = d);
    }
  }

  Future<void> _saveExpense() async {
    final desc = _expenseDescCtrl.text.trim();
    final amount =
        double.tryParse(_expenseAmountCtrl.text.trim()) ?? 0.0;
    if (desc.isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Enter a valid description and amount.',
              style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: Colors.red.shade600));
      return;
    }
    setState(() => _savingExpense = true);
    try {
      await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .collection('propertyExpenses')
          .add({
        'propertySlug': widget.propertyId,
        'description': desc,
        'amount': amount,
        'date': Timestamp.fromDate(_expenseDate),
        'createdAt': FieldValue.serverTimestamp(),
      });
      _expenseDescCtrl.clear();
      _expenseAmountCtrl.clear();
      setState(() {
        _expenseDate = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Expense saved',
              style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: Colors.teal.shade700));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save expense: $e',
              style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: Colors.red.shade600));
    } finally {
      if (mounted) setState(() => _savingExpense = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = const Color(0xFF008080);
    final blue = const Color(0xFF2196F3);

    // Single source of truth: only verified bookings for this property
    final bookingsStream = FirebaseFirestore.instance
        .collection('bookings')
        .where('propertySlug', isEqualTo: widget.propertyId)
        .where('status', isEqualTo: 'verified')
        .snapshots();

    final expensesStream = FirebaseFirestore.instance
        .collection('properties')
        .doc(widget.propertyId)
        .collection('propertyExpenses')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: bookingsStream,
      builder: (context, bookingSnap) {
        // Empty/error state: still show dashboard and calendar with 0 markers (no red error screen)
        final hasError = bookingSnap.hasError;
        final isLoading = bookingSnap.connectionState == ConnectionState.waiting;
        final bookings = hasError ? <QueryDocumentSnapshot<Map<String, dynamic>>>[] : (bookingSnap.data?.docs ?? const []);

        double totalEarnings = 0.0;
        int nightsBooked = 0;
        int activeGuests = 0;

        final Map<String, double> monthlyRevenue = {};
        final Map<DateTime, int> dailyCounts = {};
        final Map<String, int> statusCounts = {
          'verified': 0,
          'rejected': 0,
          'pending': 0,
        };

        // Range-to-date expansion: for every verified booking, loop each day between checkIn and checkOut
        for (final doc in bookings) {
          final data = doc.data();
          final total = (data['totalPrice'] as num?)?.toDouble() ?? 0.0;
          statusCounts['verified'] = (statusCounts['verified'] ?? 0) + 1;
          totalEarnings += total;
          nightsBooked += _calcNights(data);
          final guests = (data['totalPax'] as num?)?.toInt() ?? 0;
          activeGuests += guests > 0 ? guests : 0;

          DateTime? when;
          final created = data['createdAt'];
          if (created is Timestamp) {
            when = created.toDate();
          } else {
            when = _asDate(data['checkInDate'] ?? data['checkIn'] ?? data['startDate']);
          }
          when ??= DateTime.now();
          final bucket = DateTime(when.year, when.month);
          final key = '${bucket.year}-${bucket.month.toString().padLeft(2, '0')}';
          monthlyRevenue[key] = (monthlyRevenue[key] ?? 0.0) + total;

          // Normalize to midnight (timezone guard); Timestamps handled via _asDate/.toDate()
          final checkIn = _asDate(
              data['checkInDate'] ?? data['checkIn'] ?? data['startDate']);
          final checkOut = _asDate(data['checkOutDate'] ??
              data['checkOut'] ??
              data['endDate']);
          if (checkIn != null && checkOut != null) {
            // Primary path: use range [checkIn, checkOut) when check-out is after check-in.
            final startDay = _dateOnly(checkIn);
            final endDay = _dateOnly(checkOut);
            if (endDay.isAfter(startDay)) {
              var cursor = startDay;
              while (cursor.isBefore(endDay)) {
                final currentDate = _dateOnly(cursor);
                dailyCounts[currentDate] =
                    (dailyCounts[currentDate] ?? 0) + 1;
                cursor = cursor.add(const Duration(days: 1));
              }
            } else {
              // Fallback: some 1-night bookings save checkIn == checkOut.
              // In that case, at least mark the check-in day as occupied.
              final currentDate = _dateOnly(checkIn);
              dailyCounts[currentDate] =
                  (dailyCounts[currentDate] ?? 0) + 1;
            }
          } else if (checkIn != null) {
            // Last resort: if we only have a single checkIn date, mark that day.
            final currentDate = _dateOnly(checkIn);
            dailyCounts[currentDate] =
                (dailyCounts[currentDate] ?? 0) + 1;
          }
        }

        // Build last 6 month buckets
        final List<_MonthBucket> lastSixMonths = [];
        final now = DateTime.now();
        for (int i = 5; i >= 0; i--) {
          final d = DateTime(now.year, now.month - i, 1);
          final key =
              '${d.year}-${d.month.toString().padLeft(2, '0')}';
          lastSixMonths.add(_MonthBucket(
            label: _monthShort(d.month),
            key: key,
            value: monthlyRevenue[key] ?? 0.0,
          ));
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: expensesStream,
          builder: (context, expenseSnap) {
            final expenses = expenseSnap.data?.docs ?? const [];
            double totalExpenses = 0.0;
            final Map<String, double> monthlyExpenses = {};
            for (final doc in expenses) {
              final data = doc.data();
              final amt =
                  (data['amount'] as num?)?.toDouble() ?? 0.0;
              totalExpenses += amt;

              DateTime? when;
              final d = data['date'];
              if (d is Timestamp) {
                when = d.toDate();
              }
              when ??= DateTime.now();
              final bucket =
                  DateTime(when.year, when.month);
              final key =
                  '${bucket.year}-${bucket.month.toString().padLeft(2, '0')}';
              monthlyExpenses[key] =
                  (monthlyExpenses[key] ?? 0.0) + amt;
            }
            final netProfit = totalEarnings - totalExpenses;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 800;
                  final crossAxisCount = constraints.maxWidth < 600
                      ? 1
                      : (constraints.maxWidth < 1000 ? 2 : 4);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Performance Overview',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Real-time view of your earnings, occupancy, and expenses.',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      GridView.count(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        shrinkWrap: true,
                        physics:
                            const NeverScrollableScrollPhysics(),
                        childAspectRatio: isMobile ? 2.1 : 2.5,
                        children: [
                          _KpiCard(
                            title: 'Total Earnings',
                            value:
                                '₱${totalEarnings.toStringAsFixed(2)}',
                            subtitle: 'Verified bookings only',
                            color: primary,
                          ),
                          _KpiCard(
                            title: 'Net Profit',
                            value:
                                '₱${netProfit.toStringAsFixed(2)}',
                            subtitle:
                                'After logged operating expenses',
                            color: blue,
                          ),
                          _KpiCard(
                            title: 'Nights Booked',
                            value: nightsBooked.toString(),
                            subtitle: 'Total verified nights',
                            color: Colors.deepPurple,
                          ),
                          _KpiCard(
                            title: 'Active Guests',
                            value: activeGuests.toString(),
                            subtitle:
                                'Guests in verified bookings',
                            color: Colors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      isMobile
                          ? Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                _buildRevenueCard(
                                    lastSixMonths,
                                    monthlyExpenses,
                                    primary,
                                    blue),
                                const SizedBox(height: 16),
                                _buildStatusCard(statusCounts),
                                const SizedBox(height: 16),
                                _buildOccupancyCard(
                                    dailyCounts),
                                const SizedBox(height: 16),
                                _buildExpenseSummaryCard(
                                    totalExpenses),
                              ],
                            )
                          : Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: _buildRevenueCard(
                                          lastSixMonths,
                                          monthlyExpenses,
                                          primary,
                                          blue),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      flex: 2,
                                      child: _buildStatusCard(
                                          statusCounts),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: _buildExpenseSummaryCard(
                                          totalExpenses),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      flex: 3,
                                      child: _buildOccupancyCard(
                                          dailyCounts),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                      const SizedBox(height: 24),
                      _buildExpenseManager(
                          context, primary, totalExpenses),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRevenueCard(
      List<_MonthBucket> revenueMonths,
      Map<String, double> monthlyExpenses,
      Color primary,
      Color blue) {
    final maxRevenue = revenueMonths.fold<double>(
        0.0, (prev, e) => math.max(prev, e.value));
    final maxExpense = monthlyExpenses.values
        .fold<double>(0.0, (prev, v) => math.max(prev, v));
    final maxValue = math.max(maxRevenue, maxExpense);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly Revenue (last 6 months)',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Hover over bars to inspect in dev tools.',
              style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 210,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: revenueMonths.map((m) {
                  final expKey = m.key;
                  final expenseValue =
                      monthlyExpenses[expKey] ?? 0.0;
                  final revRatio = m.value / safeMax;
                  final expRatio = expenseValue / safeMax;
                  final revHeight = 30 + revRatio * 110;
                  final expHeight = 30 + expRatio * 110;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4.0),
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.end,
                        children: [
                          Text(
                            '₱${m.value.toStringAsFixed(0)} / ₱${expenseValue.toStringAsFixed(0)}',
                            style: GoogleFonts.poppins(
                                fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Container(
                                  height: revHeight,
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    gradient: LinearGradient(
                                      begin:
                                          Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        primary,
                                        primary.withValues(
                                            alpha: 0.4),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Container(
                                  height: expHeight,
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    gradient: LinearGradient(
                                      begin:
                                          Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        blue,
                                        blue.withValues(
                                            alpha: 0.4),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            m.label,
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text('Revenue',
                    style: GoogleFonts.poppins(fontSize: 11)),
                const SizedBox(width: 12),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: blue,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text('Expenses',
                    style: GoogleFonts.poppins(fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(Map<String, int> statusCounts) {
    final verified = statusCounts['verified'] ?? 0;
    final rejected = statusCounts['rejected'] ?? 0;
    final pending = statusCounts['pending'] ?? 0;
    final total = verified + rejected + pending;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Booking Status Distribution',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              total == 0
                  ? 'No bookings yet.'
                  : 'Share of verified, pending and rejected bookings.',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: 140,
                height: 140,
                child: CustomPaint(
                  painter: _PiePainter(
                    verified: verified,
                    rejected: rejected,
                    pending: pending,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _legendItem(
                color: Colors.teal, label: 'Verified', value: verified),
            _legendItem(
                color: Colors.orange,
                label: 'Pending',
                value: pending),
            _legendItem(
                color: Colors.red, label: 'Rejected', value: rejected),
          ],
        ),
      ),
    );
  }

  Widget _buildOccupancyCard(
      Map<DateTime, int> dailyCounts) {
    final teal = const Color(0xFF008080);
    final firstDay =
        DateTime(DateTime.now().year - 1, 1, 1);
    final lastDay =
        DateTime(DateTime.now().year + 1, 12, 31);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Occupancy Calendar',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'See which days are booked. Tap a date to jump to bookings for that day.',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            TableCalendar(
              firstDay: firstDay,
              lastDay: lastDay,
              focusedDay: _focusedDay,
              calendarFormat: CalendarFormat.month,
              headerStyle: HeaderStyle(
                titleCentered: true,
                formatButtonVisible: false,
                titleTextStyle: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey.shade700),
                weekendStyle: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey.shade700),
              ),
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: teal.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: teal,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle:
                    const TextStyle(color: Colors.white),
                todayTextStyle: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600),
                defaultTextStyle:
                    GoogleFonts.poppins(fontSize: 13),
                weekendTextStyle:
                    GoogleFonts.poppins(fontSize: 13),
                outsideDaysVisible: false,
              ),
              selectedDayPredicate: (day) =>
                  _selectedDay != null &&
                  day.year == _selectedDay!.year &&
                  day.month == _selectedDay!.month &&
                  day.day == _selectedDay!.day,
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                final normalized = DateTime(
                    selectedDay.year,
                    selectedDay.month,
                    selectedDay.day);
                widget.onDateSelected?.call(normalized);
              },
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
                  final key = _dateOnly(day);
                  final count = dailyCounts[key] ?? 0;
                  if (count <= 0) return const SizedBox.shrink();
                  return Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      margin: const EdgeInsets.only(top: 4, right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: teal,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: teal.withOpacity(0.4),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        '$count',
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(
      {required Color color,
      required String label,
      required int value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.poppins(fontSize: 12),
          ),
          const Spacer(),
          Text(
            value.toString(),
            style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseManager(
      BuildContext context, Color primary, double totalExpenses) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Expense Manager',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Log utilities, cleaning, and other operating costs. '
              'These are deducted from earnings to compute Net Profit.',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _expenseDescCtrl,
                    decoration: InputDecoration(
                      labelText: 'Description (e.g. Meralco, Cleaning)',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _expenseAmountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount (₱)',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: _pickExpenseDate,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Date',
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(12)),
                      ),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_expenseDate.year}-${_expenseDate.month.toString().padLeft(2, '0')}-${_expenseDate.day.toString().padLeft(2, '0')}',
                            style: GoogleFonts.poppins(
                                fontSize: 13),
                          ),
                          const Icon(Icons.calendar_today,
                              size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _savingExpense ? null : _saveExpense,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 10),
                ),
                child: _savingExpense
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('Log Expense',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Total logged expenses: ₱${totalExpenses.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey.shade800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseSummaryCard(double totalExpenses) {
    final primary = const Color(0xFF008080);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Expenses',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '₱${totalExpenses.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.redAccent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to review every logged cost.',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ExpenseListPage(
                      propertyId: widget.propertyId,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
              child: Text('View list',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  String _monthShort(int month) {
    const labels = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return labels[(month - 1).clamp(0, 11)];
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  const _KpiCard({
    Key? key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthBucket {
  final String label;
  final String key;
  final double value;

  _MonthBucket({required this.label, required this.key, required this.value});
}

class _PiePainter extends CustomPainter {
  final int verified;
  final int rejected;
  final int pending;

  _PiePainter({
    required this.verified,
    required this.rejected,
    required this.pending,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = verified + rejected + pending;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2;

    final bgPaint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    if (total == 0) {
      return;
    }

    double startAngle = -math.pi / 2;

    void drawSlice(int value, Color color) {
      if (value <= 0) return;
      final sweep = (value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweep,
          true,
          paint);
      startAngle += sweep;
    }

    drawSlice(verified, Colors.teal);
    drawSlice(pending, Colors.orange);
    drawSlice(rejected, Colors.red);

    final holePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.55, holePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class ExpenseListPage extends StatelessWidget {
  final String propertyId;

  const ExpenseListPage({Key? key, required this.propertyId})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final primary = const Color(0xFF008080);
    return Scaffold(
      appBar: AppBar(
        title: Text('Expense Breakdown',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('properties')
            .doc(propertyId)
            .collection('propertyExpenses')
            .orderBy('date', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? const [];
          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No expenses logged yet.',
                style: GoogleFonts.poppins(
                    color: Colors.grey.shade700),
              ),
            );
          }

          double total = 0.0;
          for (final d in docs) {
            total +=
                (d['amount'] as num?)?.toDouble() ?? 0.0;
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                color: primary.withOpacity(0.04),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Text(
                  'Total: ₱${total.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final desc = data['description']
                            ?.toString() ??
                        '';
                    final amt =
                        (data['amount'] as num?)?.toDouble() ??
                            0.0;
                    final ts = data['date'];
                    DateTime? d;
                    if (ts is Timestamp) {
                      d = ts.toDate();
                    }
                    final dateStr = d != null
                        ? '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
                        : 'No date';

                    return ListTile(
                      title: Text(
                        desc.isEmpty
                            ? 'Untitled expense'
                            : desc,
                        style: GoogleFonts.poppins(),
                      ),
                      subtitle: Text(
                        dateStr,
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey.shade700),
                      ),
                      trailing: Text(
                        '₱${amt.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

