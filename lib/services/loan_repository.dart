import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'member_repository.dart';

class LoanAccount {
  final String id;
  final String memberId;
  final double principal;
  final DateTime disbursedOn;
  final DateTime createdAt;

  const LoanAccount({
    required this.id,
    required this.memberId,
    required this.principal,
    required this.disbursedOn,
    required this.createdAt,
  });

  factory LoanAccount.fromMap(Map<String, dynamic> row) {
    return LoanAccount(
      id: row['id'] as String,
      memberId: row['member_id'] as String,
      principal: (row['principal'] as num).toDouble(),
      disbursedOn: DateTime.parse(row['disbursed_on'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  LoanBalance balanceOn(List<LoanRepayment> repayments, DateTime asOf) {
    final loanDate = DateTime(
      disbursedOn.year,
      disbursedOn.month,
      disbursedOn.day,
    );
    final endDate = DateTime(asOf.year, asOf.month, asOf.day);
    final relevantPayments = repayments
        .where(
          (payment) => payment.loanId == id && !payment.paidOn.isAfter(endDate),
        )
        .toList();

    var accruedInterest = _roundCurrency(principal * 0.02);
    var accrualMonth = DateTime(loanDate.year, loanDate.month + 1);
    while (!accrualMonth.isAfter(endDate)) {
      final principalPaidBeforeMonth = relevantPayments
          .where((payment) => payment.paidOn.isBefore(accrualMonth))
          .fold<double>(0, (sum, payment) => sum + payment.principalPaid);
      final principalAtMonthStart = (principal - principalPaidBeforeMonth)
          .clamp(0.0, principal);
      accruedInterest = _roundCurrency(
        accruedInterest + principalAtMonthStart * 0.02,
      );
      accrualMonth = DateTime(accrualMonth.year, accrualMonth.month + 1);
    }

    final principalPaid = relevantPayments.fold<double>(
      0,
      (sum, payment) => sum + payment.principalPaid,
    );
    final interestPaid = relevantPayments.fold<double>(
      0,
      (sum, payment) => sum + payment.interestPaid,
    );
    final principalRemaining = _roundCurrency(
      (principal - principalPaid).clamp(0.0, principal),
    );
    final interestRemaining = _roundCurrency(
      (accruedInterest - interestPaid).clamp(0.0, accruedInterest),
    );

    return LoanBalance(
      principalRemaining: principalRemaining,
      interestRemaining: principalRemaining == 0
          ? 0
          : _roundCurrency(
              interestRemaining > principalRemaining * 0.02
                  ? interestRemaining
                  : principalRemaining * 0.02,
            ),
    );
  }
}

class LoanBalance {
  final double principalRemaining;
  final double interestRemaining;

  const LoanBalance({
    required this.principalRemaining,
    required this.interestRemaining,
  });

  double get monthlyInterest => _roundCurrency(principalRemaining * 0.02);

  bool get isSettled => principalRemaining < 0.01;
}

class LoanRepayment {
  final String id;
  final String loanId;
  final double amount;
  final double interestPaid;
  final double principalPaid;
  final DateTime paidOn;
  final DateTime createdAt;

  const LoanRepayment({
    required this.id,
    required this.loanId,
    required this.amount,
    required this.interestPaid,
    required this.principalPaid,
    required this.paidOn,
    required this.createdAt,
  });

  factory LoanRepayment.fromMap(Map<String, dynamic> row) {
    return LoanRepayment(
      id: row['id'] as String,
      loanId: row['loan_id'] as String,
      amount: (row['amount'] as num).toDouble(),
      interestPaid: (row['interest_paid'] as num).toDouble(),
      principalPaid: (row['principal_paid'] as num).toDouble(),
      paidOn: DateTime.parse(row['paid_on'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

class LoanOverview {
  final List<Member> members;
  final List<LoanAccount> loans;
  final List<LoanRepayment> repayments;

  const LoanOverview({
    required this.members,
    required this.loans,
    required this.repayments,
  });
}

class LoanRepository {
  final SupabaseClient _client;

  const LoanRepository(this._client);

  Future<LoanOverview> fetchOverview() async {
    final rows = await Future.wait([
      _client
          .from('loans')
          .select('id, member_id, principal, disbursed_on, created_at')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10)),
      _client
          .from('loan_repayments')
          .select(
            'id, loan_id, amount, interest_paid, principal_paid, paid_on, created_at',
          )
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .timeout(const Duration(seconds: 10)),
      _client
          .from('members')
          .select('id, name, phone, created_at')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10)),
    ]);
    final loanRows = rows[0];
    final repaymentRows = rows[1];
    final memberRows = rows[2];

    return LoanOverview(
      members: memberRows.map(Member.fromMap).toList(),
      loans: loanRows.map(LoanAccount.fromMap).toList(),
      repayments: repaymentRows.map(LoanRepayment.fromMap).toList(),
    );
  }

  Future<void> createLoan({
    required String memberId,
    required double principal,
    required DateTime disbursedOn,
  }) async {
    await _client
        .from('loans')
        .insert({
          'member_id': memberId,
          'principal': principal,
          'disbursed_on': _dateOnly(disbursedOn),
        })
        .timeout(const Duration(seconds: 10));
  }

  Future<void> recordRepayment({
    required String loanId,
    required double interestPaid,
    required double principalPaid,
    required DateTime paidOn,
  }) async {
    await _client
        .rpc(
          'record_loan_repayment',
          params: {
            'p_loan_id': loanId,
            'p_interest_paid': interestPaid,
            'p_principal_paid': principalPaid,
            'p_paid_on': _dateOnly(paidOn),
          },
        )
        .timeout(const Duration(seconds: 10));
  }

  Future<void> editRepayment({
    required String repaymentId,
    required double interestPaid,
    required double principalPaid,
    required DateTime paidOn,
  }) async {
    await _client
        .rpc(
          'edit_loan_repayment',
          params: {
            'p_repayment_id': repaymentId,
            'p_interest_paid': interestPaid,
            'p_principal_paid': principalPaid,
            'p_paid_on': _dateOnly(paidOn),
          },
        )
        .timeout(const Duration(seconds: 10));
  }

  Future<void> deleteRepayment(String repaymentId) async {
    await _client
        .rpc('delete_loan_repayment', params: {'p_repayment_id': repaymentId})
        .timeout(const Duration(seconds: 10));
  }

  String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

double _roundCurrency(double amount) => (amount * 100).round() / 100;
