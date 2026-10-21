import 'package:flutter_application_1/finance/finance_shared_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats finance month names in Marathi', () {
    expect(formatMarathiMonthYear(DateTime(2026, 10)), 'ऑक्टोबर 2026');
  });
}
