class PricingEngine {
  /// Calculates the total booking price based on ZenStay's core variables.
  static double calculateTotal({
    required Map<String, double> weekdayRates, // Mon-Thu rates
    required Map<String, double> weekendRates, // Fri-Sun/Holiday rates
    required String selectedDuration, // '8h', '10h', '12h', or '22h'
    required DateTime checkInDate,
    required int totalPax,
    required int includedPax,
    required double extraPaxFee,
    required double securityDeposit,
    String pricingModel = 'flat_rate',
  }) {
    // 1. Check if it's a weekend (Friday, Saturday, Sunday)
    bool isWeekend = checkInDate.weekday == DateTime.friday ||
        checkInDate.weekday == DateTime.saturday ||
        checkInDate.weekday == DateTime.sunday;

    // 2. Fetch the correct base rate from the appropriate map
    double baseRate = isWeekend
        ? (weekendRates[selectedDuration] ?? 0.0)
        : (weekdayRates[selectedDuration] ?? 0.0);

    double totalCost = 0.0;

    if (pricingModel == 'per_person') {
      // Per person pricing: baseRate multiplied by number of guests
      totalCost = baseRate * totalPax;
    } else {
      // Flat rate (fixed room price) + extra pax fees if over capacity
      totalCost = baseRate;
      if (totalPax > includedPax) {
        int extraHeads = totalPax - includedPax;
        totalCost += (extraHeads * extraPaxFee);
      }
    }

    // Always add security deposit
    totalCost += securityDeposit;

    return totalCost;
  }
}
