import 'dart:async';

import 'package:flutter_application_1/services/finance_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Member {
  final String id;
  final String name;
  final String? phone;
  final DateTime createdAt;

  const Member({
    required this.id,
    required this.name,
    required this.phone,
    required this.createdAt,
  });

  factory Member.fromMap(Map<String, dynamic> row) {
    return Member(
      id: row['id'] as String,
      name: row['name'] as String,
      phone: row['phone'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

class SavingsPayment {
  final String id;
  final String memberId;
  final DateTime contributionMonth;
  final DateTime paidOn;
  final int amount;
  final FinancePaymentMethod paymentMethod;

  const SavingsPayment({
    required this.id,
    required this.memberId,
    required this.contributionMonth,
    required this.paidOn,
    required this.amount,
    required this.paymentMethod,
  });

  factory SavingsPayment.fromMap(Map<String, dynamic> row) {
    return SavingsPayment(
      id: row['id'] as String,
      memberId: row['member_id'] as String,
      contributionMonth: DateTime.parse(row['contribution_month'] as String),
      paidOn: DateTime.parse(row['paid_on'] as String),
      amount: (row['amount'] as num).toInt(),
      paymentMethod: switch (row['payment_method'] as String) {
        'cash' => FinancePaymentMethod.cash,
        'upi' => FinancePaymentMethod.upi,
        final value => throw FormatException(
          'Unknown savings payment method: $value',
        ),
      },
    );
  }
}

class SavingsOverview {
  final List<Member> members;
  final List<SavingsPayment> payments;

  const SavingsOverview({required this.members, required this.payments});
}

class MemberRepository {
  final SupabaseClient _client;
  late final Stream<List<Member>> members = _client
      .from('members')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(Member.fromMap).toList())
      .asBroadcastStream();
  late final Stream<int> memberCount = members
      .map((members) => members.length)
      .asBroadcastStream();
  MemberRepository(this._client);

  Future<List<Member>> fetchMembers() async {
    final rows = await _client
        .from('members')
        .select('id, name, phone, created_at')
        .order('created_at', ascending: false)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException(
            'Supabase did not respond within 10 seconds. Check that the project '
            'is active and the device has an internet connection.',
          ),
        );
    return rows.map(Member.fromMap).toList();
  }

  Future<SavingsOverview> fetchSavingsOverview() async {
    final memberRows = await _client
        .from('members')
        .select()
        .order('created_at', ascending: false);
    final paymentRows = await _client
        .from('monthly_savings')
        .select()
        .order('contribution_month', ascending: false);

    return SavingsOverview(
      members: memberRows.map(Member.fromMap).toList(),
      payments: paymentRows.map(SavingsPayment.fromMap).toList(),
    );
  }

  Future<List<SavingsPayment>> fetchPaymentHistory(String memberId) async {
    final rows = await _client
        .from('monthly_savings')
        .select()
        .eq('member_id', memberId)
        .order('contribution_month', ascending: false);
    return rows.map(SavingsPayment.fromMap).toList();
  }

  Future<void> addMember({required String name, required String phone}) async {
    await _client.from('members').insert({
      'name': name,
      'phone': phone.isEmpty ? null : phone,
    });
  }

  Future<void> recordSavingsPayment({
    required String memberId,
    required DateTime contributionMonth,
    required DateTime paidOn,
    required FinancePaymentMethod paymentMethod,
  }) async {
    await _client.from('monthly_savings').insert({
      'member_id': memberId,
      'contribution_month': _dateOnly(
        DateTime(contributionMonth.year, contributionMonth.month),
      ),
      'paid_on': _dateOnly(paidOn),
      'payment_method': switch (paymentMethod) {
        FinancePaymentMethod.cash => 'cash',
        FinancePaymentMethod.upi => 'upi',
      },
    });
  }

  String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
