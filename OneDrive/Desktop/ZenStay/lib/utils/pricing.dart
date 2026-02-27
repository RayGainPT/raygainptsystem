class PricingResult {
  final num baseRate;
  final num weekendPremiumAdded;
  final int extraPaxCount;
  final num extraPaxFeeTotal;
  final num securityDeposit;
  final num total;

  PricingResult({
    required this.baseRate,
    required this.weekendPremiumAdded,
    required this.extraPaxCount,
    required this.extraPaxFeeTotal,
    required this.securityDeposit,
    required this.total,
  });

  Map<String, dynamic> toMap() => {
        'baseRate': baseRate,
        'weekendPremiumAdded': weekendPremiumAdded,
        'extraPaxCount': extraPaxCount,
        'extraPaxFeeTotal': extraPaxFeeTotal,
        'securityDeposit': securityDeposit,
        'total': total,
      };
}

/// Calculate total price for a booking.
///
/// pricingConfig expected shape:
/// {
///   'baseRates': { '8h': 1199, '12h': 1399, '22h': 1599 },
///   'weekendPremium': 100,
///   'extraPaxFee': 300,
///   'maxPax': 4,
///   'securityDeposit': 1000,
/// }
PricingResult calculateTotalPrice({
  required Map<String, dynamic> pricingConfig,
  required String durationKey,
  required DateTime checkIn,
  required int paxCount,
  bool includeSecurityDeposit = true,
}) {
  // Safely read config values with sensible defaults
  final baseRates = <String, num>{};
  if (pricingConfig['baseRates'] is Map) {
    (pricingConfig['baseRates'] as Map).forEach((k, v) {
      try {
        baseRates['$k'] = (v is num) ? v : num.parse('$v');
      } catch (_) {}
    });
  }

  final num baseRate = baseRates[durationKey] ??
      (throw ArgumentError('Unknown duration: $durationKey'));
  final num weekendPremium = (pricingConfig['weekendPremium'] is num)
      ? pricingConfig['weekendPremium'] as num
      : num.tryParse('${pricingConfig['weekendPremium']}') ?? 0;

  final num extraPaxFeeEach = (pricingConfig['extraPaxFee'] is num)
      ? pricingConfig['extraPaxFee'] as num
      : num.tryParse('${pricingConfig['extraPaxFee']}') ?? 0;

  final int maxPax = (pricingConfig['maxPax'] is int)
      ? pricingConfig['maxPax'] as int
      : int.tryParse('${pricingConfig['maxPax']}') ?? 0;

  final num securityDeposit = includeSecurityDeposit
      ? ((pricingConfig['securityDeposit'] is num)
          ? pricingConfig['securityDeposit'] as num
          : num.tryParse('${pricingConfig['securityDeposit']}') ?? 0)
      : 0;

  // Weekend detection: Friday (5), Saturday (6), Sunday (7)
  final bool isWeekend = checkIn.weekday >= DateTime.friday;
  final num weekendPremiumAdded = isWeekend ? weekendPremium : 0;

  final int extraPaxCount = paxCount > maxPax ? (paxCount - maxPax) : 0;
  final num extraPaxFeeTotal = extraPaxCount * extraPaxFeeEach;

  final num total =
      baseRate + weekendPremiumAdded + extraPaxFeeTotal + securityDeposit;

  return PricingResult(
    baseRate: baseRate,
    weekendPremiumAdded: weekendPremiumAdded,
    extraPaxCount: extraPaxCount,
    extraPaxFeeTotal: extraPaxFeeTotal,
    securityDeposit: securityDeposit,
    total: total,
  );
}
