
library;

import 'package:intl/intl.dart';

class DateUtils {
  /// Formats a date string or DateTime object to 'DD/MM' format.
  static String formatToDayMonth(dynamic date) {
    if (date == null) return '';
    try {
      if (date is DateTime) {
        return DateFormat('dd/MM').format(date);
      } else if (date is String) {
        return DateFormat('dd/MM').format(DateTime.parse(date));
      }
    } catch (e) {
      // Fallback for unexpected formats
      return '';
    }
    return '';
  }
}
