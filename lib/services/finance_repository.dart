import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

enum FinanceTransactionType { deposit, expense }

enum FinancePaymentMethod { cash, upi }

String financePaymentMethodLabel(FinancePaymentMethod method) =>
    switch (method) {
      FinancePaymentMethod.cash => 'रोख',
      FinancePaymentMethod.upi => 'UPI',
    };

class FinanceTransaction {
  final String id;
  final FinanceTransactionType type;
  final FinancePaymentMethod paymentMethod;
  final double amount;
  final String? description;
  final DateTime transactionDate;

  const FinanceTransaction({
    required this.id,
    required this.type,
    required this.paymentMethod,
    required this.amount,
    required this.description,
    required this.transactionDate,
  });

  factory FinanceTransaction.fromMap(Map<String, dynamic> row) {
    return FinanceTransaction(
      id: row['id'] as String,
      type: switch (row['transaction_type'] as String) {
        'deposit' => FinanceTransactionType.deposit,
        'expense' => FinanceTransactionType.expense,
        final value => throw FormatException(
          'Unknown finance transaction type: $value',
        ),
      },
      paymentMethod: switch (row['payment_method'] as String) {
        'cash' => FinancePaymentMethod.cash,
        'upi' => FinancePaymentMethod.upi,
        final value => throw FormatException(
          'Unknown finance payment method: $value',
        ),
      },
      amount: (row['amount'] as num).toDouble(),
      description: row['description'] as String?,
      transactionDate: DateTime.parse(row['transaction_date'] as String),
    );
  }
}

class FinanceRepository {
  final SupabaseClient _client;

  const FinanceRepository(this._client);

  Future<List<FinanceTransaction>> fetchTransactions(DateTime month) async {
    final firstDay = DateTime(month.year, month.month);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final rows = await _client
        .from('finance_transactions')
        .select(
          'id, transaction_type, payment_method, amount, description, transaction_date',
        )
        .gte('transaction_date', _dateOnly(firstDay))
        .lte('transaction_date', _dateOnly(lastDay))
        .order('transaction_date', ascending: false)
        .order('created_at', ascending: false)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException(
            'व्यवहारांची माहिती 10 सेकंदांत मिळाली नाही. इंटरनेट आणि Supabase तपासा.',
          ),
        );
    return rows.map(FinanceTransaction.fromMap).toList();
  }

  Future<void> addTransaction({
    required FinanceTransactionType type,
    required FinancePaymentMethod paymentMethod,
    required double amount,
    required DateTime transactionDate,
    required String? description,
  }) async {
    await _client
        .from('finance_transactions')
        .insert({
          'transaction_type': switch (type) {
            FinanceTransactionType.deposit => 'deposit',
            FinanceTransactionType.expense => 'expense',
          },
          'payment_method': switch (paymentMethod) {
            FinancePaymentMethod.cash => 'cash',
            FinancePaymentMethod.upi => 'upi',
          },
          'amount': amount,
          'transaction_date': _dateOnly(transactionDate),
          'description': description?.trim().isEmpty ?? true
              ? null
              : description!.trim(),
        })
        .timeout(const Duration(seconds: 10));
  }

  String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
