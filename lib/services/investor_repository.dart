import 'dart:async';

import 'package:flutter_application_1/services/finance_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Investor {
  final String id;
  final String name;
  final DateTime createdAt;

  const Investor({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory Investor.fromMap(Map<String, dynamic> row) {
    return Investor(
      id: row['id'] as String,
      name: row['name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

enum InvestorTransactionType { contribution, interestPayout, principalPayout }

class InvestorTransaction {
  final String id;
  final String investorId;
  final InvestorTransactionType type;
  final double amount;
  final DateTime transactionDate;
  final FinancePaymentMethod paymentMethod;

  const InvestorTransaction({
    required this.id,
    required this.investorId,
    required this.type,
    required this.amount,
    required this.transactionDate,
    required this.paymentMethod,
  });

  factory InvestorTransaction.fromMap(Map<String, dynamic> row) {
    return InvestorTransaction(
      id: row['id'] as String,
      investorId: row['investor_id'] as String,
      type: switch (row['transaction_type'] as String) {
        'contribution' => InvestorTransactionType.contribution,
        'interest_payout' => InvestorTransactionType.interestPayout,
        'principal_payout' => InvestorTransactionType.principalPayout,
        final value => throw FormatException(
          'Unknown investor transaction type: $value',
        ),
      },
      amount: (row['amount'] as num).toDouble(),
      transactionDate: DateTime.parse(row['transaction_date'] as String),
      paymentMethod: switch (row['payment_method'] as String) {
        'cash' => FinancePaymentMethod.cash,
        'upi' => FinancePaymentMethod.upi,
        final value => throw FormatException(
          'Unknown investor payment method: $value',
        ),
      },
    );
  }
}

class InvestorBalance {
  final String investorId;
  final String name;
  final double principalRemaining;
  final double interestDue;

  const InvestorBalance({
    required this.investorId,
    required this.name,
    required this.principalRemaining,
    required this.interestDue,
  });

  factory InvestorBalance.fromMap(Map<String, dynamic> row) {
    return InvestorBalance(
      investorId: row['investor_id'] as String,
      name: row['name'] as String,
      principalRemaining: (row['principal_remaining'] as num).toDouble(),
      interestDue: (row['interest_due'] as num).toDouble(),
    );
  }
}

class InvestorOverview {
  final List<InvestorBalance> balances;
  final List<InvestorTransaction> transactions;

  const InvestorOverview({required this.balances, required this.transactions});
}

class InvestorRepository {
  final SupabaseClient _client;

  const InvestorRepository(this._client);

  Future<InvestorOverview> fetchOverview() async {
    final rows = await Future.wait([
      _client
          .rpc(
            'investor_balances',
            params: {'p_as_of': _dateOnly(DateTime.now())},
          )
          .timeout(const Duration(seconds: 10)),
      _client
          .from('investor_transactions')
          .select(
            'id, investor_id, transaction_type, amount, transaction_date, payment_method',
          )
          .order('transaction_date', ascending: false)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10)),
    ]);

    final balanceRows = (rows[0] as List).cast<Map<String, dynamic>>();
    final transactionRows = (rows[1] as List).cast<Map<String, dynamic>>();

    return InvestorOverview(
      balances: balanceRows.map(InvestorBalance.fromMap).toList(),
      transactions: transactionRows.map(InvestorTransaction.fromMap).toList(),
    );
  }

  Future<void> addContribution({
    required String? investorId,
    required String? investorName,
    required double amount,
    required DateTime transactionDate,
    required FinancePaymentMethod paymentMethod,
  }) async {
    await _client
        .rpc(
          'add_investor_contribution',
          params: {
            'p_investor_id': investorId,
            'p_investor_name': investorName,
            'p_amount': amount,
            'p_transaction_date': _dateOnly(transactionDate),
            'p_payment_method': switch (paymentMethod) {
              FinancePaymentMethod.cash => 'cash',
              FinancePaymentMethod.upi => 'upi',
            },
          },
        )
        .timeout(const Duration(seconds: 10));
  }

  Future<void> recordPayout({
    required String investorId,
    required double interestAmount,
    required double principalAmount,
    required DateTime paidOn,
    required FinancePaymentMethod paymentMethod,
  }) async {
    await _client
        .rpc(
          'record_investor_payout',
          params: {
            'p_investor_id': investorId,
            'p_interest_amount': interestAmount,
            'p_principal_amount': principalAmount,
            'p_paid_on': _dateOnly(paidOn),
            'p_payment_method': switch (paymentMethod) {
              FinancePaymentMethod.cash => 'cash',
              FinancePaymentMethod.upi => 'upi',
            },
          },
        )
        .timeout(const Duration(seconds: 10));
  }

  String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
