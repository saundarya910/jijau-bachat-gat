import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/finance_repository.dart';

class FinanceMonthSelector extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool canGoNext;

  const FinanceMonthSelector({
    super.key,
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.canGoNext,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'मागील महिना',
          ),
          Text(
            formatMarathiMonthYear(month),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          IconButton(
            onPressed: canGoNext ? onNext : null,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'पुढील महिना',
          ),
        ],
      ),
    );
  }
}

String formatMarathiMonthYear(DateTime date) {
  const months = [
    'जानेवारी',
    'फेब्रुवारी',
    'मार्च',
    'एप्रिल',
    'मे',
    'जून',
    'जुलै',
    'ऑगस्ट',
    'सप्टेंबर',
    'ऑक्टोबर',
    'नोव्हेंबर',
    'डिसेंबर',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

class PaymentMethodSelector extends StatelessWidget {
  final FinancePaymentMethod value;
  final ValueChanged<FinancePaymentMethod> onChanged;

  const PaymentMethodSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<FinancePaymentMethod>(
      segments: const [
        ButtonSegment(
          value: FinancePaymentMethod.cash,
          label: Text('रोख'),
          icon: Icon(Icons.payments_outlined),
        ),
        ButtonSegment(
          value: FinancePaymentMethod.upi,
          label: Text('UPI'),
          icon: Icon(Icons.phone_android),
        ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class FinanceMetric extends StatelessWidget {
  final String label;
  final double amount;
  final IconData icon;
  final Color color;

  const FinanceMetric({
    super.key,
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 164,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 3),
              Text(
                formatMoney(amount),
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FinanceReportCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final Color color;

  const FinanceReportCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(detail),
        trailing: Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        isThreeLine: true,
      ),
    );
  }
}

class FinanceTransactionTile extends StatelessWidget {
  final FinanceTransaction transaction;

  const FinanceTransactionTile({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isDeposit = transaction.type == FinanceTransactionType.deposit;
    final color = isDeposit ? const Color(0xFF218838) : const Color(0xFFC62828);
    final method = transaction.paymentMethod == FinancePaymentMethod.cash
        ? 'रोख'
        : 'UPI';
    final description = transaction.description?.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(
            isDeposit ? Icons.south_west : Icons.north_east,
            color: color,
          ),
        ),
        title: Text(isDeposit ? 'जमा • $method' : 'खर्च • $method'),
        subtitle: Text(
          [
            formatDate(transaction.transactionDate),
            if (description != null && description.isNotEmpty) description,
          ].join(' • '),
        ),
        trailing: Text(
          '${isDeposit ? '+' : '-'}${formatMoney(transaction.amount)}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        isThreeLine: description != null && description.isNotEmpty,
      ),
    );
  }
}

class FinanceLoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const FinanceLoadError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF4F4F4),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 58,
                color: Color(0xFFE53935),
              ),
              const SizedBox(height: 18),
              const Text(
                'माहिती लोड करता आली नाही.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1C1C1C),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF4C4C4C)),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1FAE5A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('पुन्हा प्रयत्न करा'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

double sumByType(
  List<FinanceTransaction> transactions,
  FinanceTransactionType type,
) => transactions
    .where((transaction) => transaction.type == type)
    .fold<double>(0, (sum, transaction) => sum + transaction.amount);

double sumByMethod(
  List<FinanceTransaction> transactions,
  FinancePaymentMethod method,
) => transactions
    .where((transaction) => transaction.paymentMethod == method)
    .fold<double>(0, (sum, transaction) => sum + transaction.amount);

bool sameMonth(DateTime first, DateTime second) =>
    first.year == second.year && first.month == second.month;

bool isCurrentMonth(DateTime month) {
  final now = DateTime.now();
  return sameMonth(month, now);
}

String formatMoney(num amount) => '₹${amount.toStringAsFixed(2)}';

String formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';
