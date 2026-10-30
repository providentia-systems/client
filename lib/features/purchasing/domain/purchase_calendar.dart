/// Purchase dates are calendar labels, never instants to convert between zones.
String formatPurchaseDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime parsePurchaseDay(String text) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    throw const FormatException('Enter a valid purchase day as YYYY-MM-DD.');
  }
  final day = DateTime.tryParse('${text}T00:00:00Z');
  if (day == null || formatPurchaseDay(day) != text) {
    throw const FormatException('Enter a valid purchase day as YYYY-MM-DD.');
  }
  return day;
}
