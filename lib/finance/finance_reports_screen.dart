import 'package:flutter/material.dart';
import 'package:flutter_application_1/finance/finance_shared_widgets.dart';
import 'package:flutter_application_1/services/loan_repository.dart';
import 'package:flutter_application_1/services/member_repository.dart';

class FinanceReportsScreen extends StatefulWidget {
  final MemberRepository members;
  final LoanRepository loans;

  const FinanceReportsScreen({
    super.key,
    required this.members,
    required this.loans,
  });

  @override
  State<FinanceReportsScreen> createState() => _FinanceReportsScreenState();
}

class _FinanceReportsScreenState extends State<FinanceReportsScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<_ReportData> _report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _report = _fetchReport();
  }

  Future<_ReportData> _fetchReport() async {
    final results = await Future.wait<dynamic>([
      widget.members.fetchSavingsOverview(),
      widget.loans.fetchOverview(),
    ]);
    return _ReportData(
      savings: results[0] as SavingsOverview,
      loans: results[1] as LoanOverview,
    );
  }

  void _changeMonth(int offset) {
    final month = DateTime(_selectedMonth.year, _selectedMonth.month + offset);
    final now = DateTime.now();
    if (month.isAfter(DateTime(now.year, now.month))) return;

    setState(() {
      _selectedMonth = month;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('अहवाल'),
        actions: [
          IconButton(
            onPressed: () => setState(_load),
            icon: const Icon(Icons.refresh),
            tooltip: 'रिफ्रेश करा',
          ),
        ],
      ),
      body: FutureBuilder<_ReportData>(
        future: _report,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FinanceLoadError(
              message: '${snapshot.error}',
              onRetry: () => setState(_load),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          final savings = data.savings.payments.where(
            (payment) => sameMonth(payment.contributionMonth, _selectedMonth),
          );
          final loansIssued = data.loans.loans.where(
            (loan) => sameMonth(loan.disbursedOn, _selectedMonth),
          );
          final repayments = data.loans.repayments.where(
            (payment) => sameMonth(payment.paidOn, _selectedMonth),
          );
          final savingsTotal = savings.fold<int>(
            0,
            (total, payment) => total + payment.amount,
          );
          final loansTotal = loansIssued.fold<double>(
            0,
            (total, loan) => total + loan.principal,
          );
          final repaymentTotal = repayments.fold<double>(
            0,
            (total, payment) => total + payment.amount,
          );
          final principalRepaid = repayments.fold<double>(
            0,
            (total, payment) => total + payment.principalPaid,
          );
          final interestReceived = repayments.fold<double>(
            0,
            (total, payment) => total + payment.interestPaid,
          );
          final now = DateTime.now();
          final monthEnd = DateTime(
            _selectedMonth.year,
            _selectedMonth.month + 1,
            0,
          );
          final asOf = sameMonth(_selectedMonth, now) && monthEnd.isAfter(now)
              ? now
              : monthEnd;
          final outstanding = data.loans.loans.fold<double>(
            0,
            (total, loan) => loan.disbursedOn.isAfter(asOf)
                ? total
                : total + loan.balanceOn(data.loans.repayments, asOf).total,
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FinanceMonthSelector(
                month: _selectedMonth,
                onPrevious: () => _changeMonth(-1),
                onNext: () => _changeMonth(1),
                canGoNext: !isCurrentMonth(_selectedMonth),
              ),
              const SizedBox(height: 18),
              const Text(
                'मासिक बचत',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              FinanceReportCard(
                icon: Icons.savings_outlined,
                title: 'जमा झालेली बचत',
                value: formatMoney(savingsTotal),
                detail: '${savings.length} सदस्यांनी भरली',
                color: const Color(0xFF218838),
              ),
              const SizedBox(height: 18),
              const Text(
                'कर्ज अहवाल',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              FinanceReportCard(
                icon: Icons.account_balance_outlined,
                title: 'या महिन्यात दिलेले कर्ज',
                value: formatMoney(loansTotal),
                detail: '${loansIssued.length} नवीन कर्जे',
                color: const Color(0xFF1769AA),
              ),
              FinanceReportCard(
                icon: Icons.payments_outlined,
                title: 'या महिन्यातील परतफेड',
                value: formatMoney(repaymentTotal),
                detail:
                    'मूळधन ${formatMoney(principalRepaid)} • व्याज ${formatMoney(interestReceived)}',
                color: const Color(0xFF6A1B9A),
              ),
              FinanceReportCard(
                icon: Icons.account_balance_wallet_outlined,
                title: 'एकूण बाकी कर्ज',
                value: formatMoney(outstanding),
                detail: 'निवडलेल्या महिन्याच्या अखेरची बाकी',
                color: const Color(0xFFC26A00),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'अहवालातील बचत व कर्जाची माहिती नोंदवलेल्या व्यवहारांवर आधारित आहे.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReportData {
  final SavingsOverview savings;
  final LoanOverview loans;

  const _ReportData({required this.savings, required this.loans});
}
