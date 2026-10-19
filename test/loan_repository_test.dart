import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/loan_repository.dart';

void main() {
  final loan = LoanAccount(
    id: 'loan-1',
    memberId: 'member-1',
    principal: 1000,
    disbursedOn: DateTime(2026, 1, 15),
    createdAt: DateTime(2026, 1, 15),
  );

  test('starts charging simple monthly interest the month after issue', () {
    final balance = loan.balanceOn([], DateTime(2026, 1, 31));
    expect(balance.principalRemaining, 1000);
    expect(balance.interestRemaining, 0);

    final nextMonth = loan.balanceOn([], DateTime(2026, 2, 1));
    expect(nextMonth.interestRemaining, 20);
    expect(nextMonth.total, 1020);
  });

  test('repayment pays accrued interest before reducing principal', () {
    final repayments = [
      LoanRepayment(
        id: 'repayment-1',
        loanId: 'loan-1',
        amount: 500,
        interestPaid: 20,
        principalPaid: 480,
        paidOn: DateTime(2026, 2, 15),
      ),
    ];

    final balance = loan.balanceOn(repayments, DateTime(2026, 3, 1));
    expect(balance.principalRemaining, 520);
    expect(balance.interestRemaining, 10.4);
    expect(balance.total, 530.4);
  });

  test('waives remaining interest when all principal has been repaid', () {
    final repayments = [
      LoanRepayment(
        id: 'repayment-1',
        loanId: 'loan-1',
        amount: 1000,
        interestPaid: 0,
        principalPaid: 1000,
        paidOn: DateTime(2026, 2, 15),
      ),
    ];

    final balance = loan.balanceOn(repayments, DateTime(2026, 3, 1));
    expect(balance.principalRemaining, 0);
    expect(balance.interestRemaining, 0);
    expect(balance.total, 0);
    expect(balance.isSettled, isTrue);
  });
}
