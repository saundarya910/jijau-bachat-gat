import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/finance_repository.dart';
import 'package:flutter_application_1/services/loan_repository.dart';

void main() {
  final loan = LoanAccount(
    id: 'loan-1',
    memberId: 'member-1',
    principal: 1000,
    disbursedOn: DateTime(2026, 1, 15),
    createdAt: DateTime(2026, 1, 15),
  );

  test('charges monthly interest immediately and at each month start', () {
    final balance = loan.balanceOn([], DateTime(2026, 1, 31));
    expect(balance.principalRemaining, 1000);
    expect(balance.interestRemaining, 20);
    expect(balance.monthlyInterest, 20);

    final nextMonth = loan.balanceOn([], DateTime(2026, 2, 1));
    expect(nextMonth.interestRemaining, 40);
    expect(nextMonth.principalRemaining, 1000);
    expect(nextMonth.monthlyInterest, 20);
  });

  test('charges on issue date and each following calendar month', () {
    final augustLoan = LoanAccount(
      id: 'august-loan',
      memberId: 'member-1',
      principal: 5000,
      disbursedOn: DateTime(2026, 8, 20),
      createdAt: DateTime(2026, 8, 20),
    );

    final balance = augustLoan.balanceOn([], DateTime(2026, 10, 19));

    expect(balance.principalRemaining, 5000);
    expect(balance.interestRemaining, 300);
    expect(balance.principalRemaining, 5000);
  });

  test('shows first month interest on the loan issue date', () {
    final sameDayLoan = LoanAccount(
      id: 'same-day-loan',
      memberId: 'member-1',
      principal: 5000,
      disbursedOn: DateTime(2026, 10, 19),
      createdAt: DateTime(2026, 10, 19),
    );

    final balance = sameDayLoan.balanceOn([], DateTime(2026, 10, 19));

    expect(balance.principalRemaining, 5000);
    expect(balance.interestRemaining, 100);
    expect(balance.principalRemaining, 5000);
  });

  test('adds a later disbursement to the same account from its date', () {
    final loanWithAdditionalAmount = LoanAccount(
      id: 'loan-1',
      memberId: 'member-1',
      principal: 1000,
      disbursedOn: DateTime(2026, 1, 15),
      createdAt: DateTime(2026, 1, 15),
      disbursements: [
        LoanDisbursement(
          id: 'disbursement-1',
          loanId: 'loan-1',
          amount: 500,
          disbursedOn: DateTime(2026, 2, 10),
          createdAt: DateTime(2026, 2, 10),
          paymentMethod: FinancePaymentMethod.upi,
        ),
      ],
    );

    final beforeAdditionalAmount = loanWithAdditionalAmount.balanceOn(
      [],
      DateTime(2026, 2, 1),
    );
    expect(beforeAdditionalAmount.principalRemaining, 1000);
    expect(beforeAdditionalAmount.interestRemaining, 40);

    final afterAdditionalAmount = loanWithAdditionalAmount.balanceOn(
      [],
      DateTime(2026, 3, 1),
    );
    expect(loanWithAdditionalAmount.totalDisbursed, 1500);
    expect(afterAdditionalAmount.principalRemaining, 1500);
    expect(afterAdditionalAmount.interestRemaining, 80);
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
        createdAt: DateTime(2026, 2, 15),
      ),
    ];

    final balance = loan.balanceOn(repayments, DateTime(2026, 3, 1));
    expect(balance.principalRemaining, 520);
    expect(balance.interestRemaining, 30.4);
    expect(balance.principalRemaining, 520);
  });

  test('keeps one month of interest due after interest is paid', () {
    final repayments = [
      LoanRepayment(
        id: 'repayment-1',
        loanId: 'loan-1',
        amount: 20,
        interestPaid: 20,
        principalPaid: 0,
        paidOn: DateTime(2026, 1, 20),
        createdAt: DateTime(2026, 1, 20),
      ),
    ];

    final balance = loan.balanceOn(repayments, DateTime(2026, 1, 20));

    expect(balance.principalRemaining, 1000);
    expect(balance.interestRemaining, 20);
  });

  test('total remaining principal ignores interest repayment amount', () {
    final fiveThousandLoan = LoanAccount(
      id: 'five-thousand-loan',
      memberId: 'member-1',
      principal: 5000,
      disbursedOn: DateTime(2026, 1, 15),
      createdAt: DateTime(2026, 1, 15),
    );
    final repayments = [
      LoanRepayment(
        id: 'repayment-1',
        loanId: 'five-thousand-loan',
        amount: 2100,
        interestPaid: 100,
        principalPaid: 2000,
        paidOn: DateTime(2026, 2, 1),
        createdAt: DateTime(2026, 2, 1),
      ),
    ];

    final balance = fiveThousandLoan.balanceOn(
      repayments,
      DateTime(2026, 2, 1),
    );

    expect(balance.principalRemaining, 3000);
    expect(balance.interestRemaining, 100);
    expect(balance.isSettled, isFalse);
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
        createdAt: DateTime(2026, 2, 15),
      ),
    ];

    final balance = loan.balanceOn(repayments, DateTime(2026, 3, 1));
    expect(balance.principalRemaining, 0);
    expect(balance.interestRemaining, 0);
    expect(balance.principalRemaining, 0);
    expect(balance.isSettled, isTrue);
  });
}
