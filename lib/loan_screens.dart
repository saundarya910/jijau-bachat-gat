import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/services/loan_repository.dart';
import 'package:flutter_application_1/services/member_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoanManagementScreen extends StatefulWidget {
  final LoanRepository loans;
  final MemberRepository members;

  const LoanManagementScreen({
    super.key,
    required this.loans,
    required this.members,
  });

  @override
  State<LoanManagementScreen> createState() => _LoanManagementScreenState();
}

class _LoanManagementScreenState extends State<LoanManagementScreen> {
  late Future<LoanOverview> _overview;

  @override
  void initState() {
    super.initState();
    _overview = widget.loans.fetchOverview();
  }

  Future<void> _reload() async {
    final request = widget.loans.fetchOverview();
    setState(() => _overview = request);
    try {
      await request;
    } on Exception catch (error) {
      if (mounted) _showError('माहिती रिफ्रेश करता आली नाही: $error');
    }
  }

  Future<void> _createLoan() async {
    List<Member> members;
    try {
      members = await widget.members.fetchMembers();
    } on Exception catch (error) {
      if (mounted) _showError('सदस्यांची यादी लोड करता आली नाही: $error');
      return;
    }
    if (!mounted) return;
    if (members.isEmpty) {
      _showError('कर्ज नोंदवण्यापूर्वी सदस्य नोंदवा.');
      return;
    }

    final created = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _CreateLoanDialog(repository: widget.loans, members: members),
    );
    if (created == true && mounted) {
      await _reload();
      _showSuccess('कर्ज नोंदवले.');
    }
  }

  Future<bool> _editRepayment(
    BuildContext context,
    LoanAccount loan,
    List<LoanRepayment> loanRepayments,
    LoanRepayment repayment,
  ) async {
    final chronological = [...loanRepayments]
      ..sort((a, b) {
        final dateOrder = a.createdAt.compareTo(b.createdAt);
        return dateOrder != 0 ? dateOrder : a.id.compareTo(b.id);
      });
    final index = chronological.indexWhere((item) => item.id == repayment.id);
    final earliest = index > 0
        ? chronological[index - 1].paidOn
        : loan.disbursedOn;
    final latest = index >= 0 && index < chronological.length - 1
        ? chronological[index + 1].paidOn
        : DateTime.now();
    final edited = await showDialog<bool>(
      context: context,
      builder: (context) => _RepaymentDialog(
        repository: widget.loans,
        loan: loan,
        balance: loan.balanceOn(loanRepayments, DateTime.now()),
        earliestPaymentDate: earliest,
        latestPaymentDate: latest,
        repaymentToEdit: repayment,
      ),
    );
    if (edited != true || !mounted) return false;
    await _reload();
    _showSuccess('परतफेड तपशील दुरुस्त केले.');
    return true;
  }

  Future<bool> _deleteRepayment(
    BuildContext context,
    LoanRepayment repayment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('परतफेड रद्द करायची?'),
        content: const Text(
          'ही परतफेड हटवल्यावर मूळधन आणि व्याजाची बाकी पुन्हा मोजली जाईल.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('नाही'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('हटवा'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    try {
      await widget.loans.deleteRepayment(repayment.id);
      if (!mounted) return false;
      await _reload();
      _showSuccess('परतफेड हटवली; बाकी पुन्हा मोजली.');
      return true;
    } on Exception catch (error) {
      if (mounted) _showError('परतफेड हटवता आली नाही: $error');
      return false;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('कर्ज व परतफेड'),
          actions: [
            IconButton(
              onPressed: () => _reload(),
              icon: const Icon(Icons.refresh),
              tooltip: 'माहिती रिफ्रेश करा',
            ),
          ],
          bottom: const TabBar(
            labelColor: Color(0xFF17652B),
            unselectedLabelColor: Colors.white,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            unselectedLabelStyle: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: Color(0xFFE0F2E4),
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
            ),
            tabs: [
              Tab(
                icon: _LoanTabIcon(icon: Icons.account_balance, tabIndex: 0),
                text: 'कर्ज खाते',
              ),
              Tab(
                icon: _LoanTabIcon(icon: Icons.receipt_long, tabIndex: 1),
                text: 'परतफेड इतिहास',
              ),
            ],
          ),
        ),
        body: FutureBuilder<LoanOverview>(
          future: _overview,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _LoadFailure(
                message: '${snapshot.error}',
                onRetry: _reload,
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            return TabBarView(
              children: [
                _LoanAccountsTab(
                  overview: snapshot.data!,
                  repository: widget.loans,
                  onReload: _reload,
                  onSuccess: _showSuccess,
                  onEdit: _editRepayment,
                  onDelete: _deleteRepayment,
                ),
                _RepaymentHistoryTab(
                  overview: snapshot.data!,
                  onEdit: (payment, loan, loanRepayments) =>
                      _editRepayment(context, loan, loanRepayments, payment),
                  onDelete: (payment) => _deleteRepayment(context, payment),
                ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _createLoan,
          icon: const Icon(Icons.add),
          label: const Text('नवीन कर्ज'),
        ),
      ),
    );
  }
}

class _LoanAccountsTab extends StatelessWidget {
  final LoanOverview overview;
  final LoanRepository repository;
  final Future<void> Function() onReload;
  final ValueChanged<String> onSuccess;
  final Future<bool> Function(
    BuildContext context,
    LoanAccount loan,
    List<LoanRepayment> loanRepayments,
    LoanRepayment repayment,
  )
  onEdit;
  final Future<bool> Function(BuildContext context, LoanRepayment repayment)
  onDelete;

  const _LoanAccountsTab({
    required this.overview,
    required this.repository,
    required this.onReload,
    required this.onSuccess,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final membersById = {
      for (final member in overview.members) member.id: member,
    };
    final balances = {
      for (final loan in overview.loans)
        loan.id: loan.balanceOn(overview.repayments, DateTime.now()),
    };
    final outstanding = balances.values.fold<double>(
      0,
      (sum, balance) => sum + balance.principalRemaining,
    );
    final openLoans = overview.loans
        .where((loan) => !(balances[loan.id]?.isSettled ?? true))
        .toList();
    final closedLoans = overview.loans
        .where((loan) => balances[loan.id]?.isSettled ?? true)
        .toList();

    if (overview.loans.isEmpty) {
      return const Center(child: Text('अजून कोणतेही कर्ज नोंदवलेले नाही.'));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Card(
          color: const Color(0xFFE0F2E4),
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet),
            title: const Text('एकूण बाकी कर्ज (मूळधन)'),
            trailing: Text(
              _money(outstanding),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        _SectionTitle(title: 'चालू कर्ज', count: openLoans.length),
        if (openLoans.isEmpty)
          const _EmptyLabel(message: 'चालू कर्ज नाही.')
        else
          ...openLoans.map(
            (loan) => _LoanCard(
              loan: loan,
              repository: repository,
              member: membersById[loan.memberId],
              balance: balances[loan.id]!,
              repayments: overview.repayments
                  .where((payment) => payment.loanId == loan.id)
                  .toList(),
              onReload: onReload,
              onSuccess: onSuccess,
              onEdit: (payment, selectedLoan, loanRepayments) =>
                  onEdit(context, selectedLoan, loanRepayments, payment),
              onDelete: (payment) => onDelete(context, payment),
            ),
          ),
        _SectionTitle(title: 'फेडलेली कर्जे', count: closedLoans.length),
        if (closedLoans.isEmpty)
          const _EmptyLabel(message: 'फेडलेले कर्ज नाही.')
        else
          ...closedLoans.map(
            (loan) => _LoanCard(
              loan: loan,
              repository: repository,
              member: membersById[loan.memberId],
              balance: balances[loan.id]!,
              repayments: overview.repayments
                  .where((payment) => payment.loanId == loan.id)
                  .toList(),
              onReload: onReload,
              onSuccess: onSuccess,
              onEdit: (payment, selectedLoan, loanRepayments) =>
                  onEdit(context, selectedLoan, loanRepayments, payment),
              onDelete: (payment) => onDelete(context, payment),
            ),
          ),
      ],
    );
  }
}

class _LoanCard extends StatelessWidget {
  final LoanAccount loan;
  final LoanRepository repository;
  final Member? member;
  final LoanBalance balance;
  final List<LoanRepayment> repayments;
  final Future<void> Function() onReload;
  final ValueChanged<String> onSuccess;
  final Future<bool> Function(
    LoanRepayment payment,
    LoanAccount loan,
    List<LoanRepayment> loanRepayments,
  )
  onEdit;
  final Future<bool> Function(LoanRepayment payment) onDelete;

  const _LoanCard({
    required this.loan,
    required this.repository,
    required this.member,
    required this.balance,
    required this.repayments,
    required this.onReload,
    required this.onSuccess,
    required this.onEdit,
    required this.onDelete,
  });

  Future<void> _recordRepayment(
    BuildContext context, {
    bool closeDetails = false,
  }) async {
    final sorted = [...repayments]
      ..sort((a, b) => a.paidOn.compareTo(b.paidOn));
    final recorded = await showDialog<bool>(
      context: context,
      builder: (context) => _RepaymentDialog(
        repository: repository,
        loan: loan,
        balance: balance,
        earliestPaymentDate: sorted.isEmpty
            ? loan.disbursedOn
            : sorted.last.paidOn,
        latestPaymentDate: DateTime.now(),
      ),
    );
    if (recorded == true) {
      await onReload();
      if (closeDetails && context.mounted) {
        Navigator.of(context).pop();
      }
      onSuccess('परतफेड नोंदवली.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => _LoanDetailsScreen(
              loan: loan,
              memberName: member?.name ?? 'सदस्य',
              balance: balance,
              repayments: repayments,
              onRecord: () => _recordRepayment(context, closeDetails: true),
              onEdit: (payment) async {
                final edited = await onEdit(payment, loan, repayments);
                if (edited && context.mounted) Navigator.of(context).pop();
                return edited;
              },
              onDelete: (payment) async {
                final deleted = await onDelete(payment);
                if (deleted && context.mounted) Navigator.of(context).pop();
                return deleted;
              },
            ),
          ),
        ),
        leading: Icon(
          balance.isSettled ? Icons.check_circle : Icons.account_balance,
          color: balance.isSettled ? const Color(0xFF218838) : Colors.blue,
        ),
        title: Text(member?.name ?? 'सदस्य उपलब्ध नाही'),
        subtitle: Text(
          'कर्ज ${_formatDate(loan.disbursedOn)} • घेतले ${_money(loan.principal)}'
          '\nमूळधन बाकी ${_money(balance.principalRemaining)}'
          ' • व्याज बाकी ${_money(balance.interestRemaining)}',
        ),
        isThreeLine: true,
        trailing: balance.isSettled
            ? const Icon(Icons.chevron_right)
            : IconButton(
                onPressed: () => _recordRepayment(context),
                icon: const Icon(
                  Icons.payments_outlined,
                  color: Color(0xFF218838),
                ),
                tooltip: 'परतफेड नोंदवा',
              ),
      ),
    );
  }
}

class _RepaymentHistoryTab extends StatelessWidget {
  final LoanOverview overview;
  final Future<bool> Function(
    LoanRepayment payment,
    LoanAccount loan,
    List<LoanRepayment> loanRepayments,
  )
  onEdit;
  final Future<bool> Function(LoanRepayment payment) onDelete;

  const _RepaymentHistoryTab({
    required this.overview,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (overview.repayments.isEmpty) {
      return const Center(child: Text('अजून परतफेड नोंदवलेली नाही.'));
    }

    final loansById = {for (final loan in overview.loans) loan.id: loan};
    final membersById = {
      for (final member in overview.members) member.id: member,
    };
    final repayments = [...overview.repayments]
      ..sort((a, b) {
        final dateOrder = b.createdAt.compareTo(a.createdAt);
        return dateOrder != 0 ? dateOrder : b.id.compareTo(a.id);
      });

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: repayments.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final payment = repayments[index];
        final loan = loansById[payment.loanId];
        final member = loan == null ? null : membersById[loan.memberId];
        return Card(
          color: Colors.white,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE0F2E4),
              child: Icon(Icons.payments, color: Color(0xFF218838)),
            ),
            title: Text(member?.name ?? 'सदस्य उपलब्ध नाही'),
            subtitle: Text(
              '${_formatDate(payment.paidOn)} • मूळधन ${_money(payment.principalPaid)}'
              ' • व्याज ${_money(payment.interestPaid)}',
            ),
            trailing: loan == null
                ? Text(
                    _money(payment.amount),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _money(payment.amount),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      _RepaymentActionsMenu(
                        onEdit: () => onEdit(
                          payment,
                          loan,
                          overview.repayments
                              .where((item) => item.loanId == loan.id)
                              .toList(),
                        ),
                        onDelete: () => onDelete(payment),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _RepaymentActionsMenu extends StatelessWidget {
  final Future<bool> Function() onEdit;
  final Future<bool> Function() onDelete;

  const _RepaymentActionsMenu({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'परतफेड बदल / हटवा',
      onSelected: (action) async {
        if (action == 'edit') {
          await onEdit();
        } else if (action == 'delete') {
          await onDelete();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('दुरुस्त करा'),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text('हटवा'),
          ),
        ),
      ],
    );
  }
}

class _LoanDetailsScreen extends StatelessWidget {
  final LoanAccount loan;
  final String memberName;
  final LoanBalance balance;
  final List<LoanRepayment> repayments;
  final VoidCallback onRecord;
  final Future<bool> Function(LoanRepayment payment) onEdit;
  final Future<bool> Function(LoanRepayment payment) onDelete;

  const _LoanDetailsScreen({
    required this.loan,
    required this.memberName,
    required this.balance,
    required this.repayments,
    required this.onRecord,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...repayments]
      ..sort((a, b) {
        final dateOrder = b.createdAt.compareTo(a.createdAt);
        return dateOrder != 0 ? dateOrder : b.id.compareTo(a.id);
      });
    final interestPaid = repayments.fold<double>(
      0,
      (sum, payment) => sum + payment.interestPaid,
    );
    return Scaffold(
      appBar: AppBar(title: Text(memberName)),
      floatingActionButton: balance.isSettled
          ? null
          : FloatingActionButton.extended(
              onPressed: onRecord,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('परतफेड नोंदवा'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Card(
            color: const Color(0xFFE0F2E4),
            child: Column(
              children: [
                ListTile(
                  title: const Text('कर्जाची रक्कम'),
                  trailing: Text(_money(loan.principal)),
                ),
                ListTile(
                  title: const Text('कर्ज दिनांक'),
                  trailing: Text(_formatDate(loan.disbursedOn)),
                ),
                ListTile(
                  title: const Text('मूळधन बाकी'),
                  trailing: Text(_money(balance.principalRemaining)),
                ),
                ListTile(
                  title: const Text('जमा व्याज'),
                  trailing: Text(_money(interestPaid)),
                ),
                ListTile(
                  title: const Text('व्याज बाकी'),
                  trailing: Text(_money(balance.interestRemaining)),
                ),
                ListTile(
                  title: const Text('एकूण बाकी (मूळधन)'),
                  trailing: Text(
                    _money(balance.principalRemaining),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          _SectionTitle(title: 'परतफेड इतिहास', count: sorted.length),
          if (sorted.isEmpty)
            const _EmptyLabel(message: 'या कर्जाची परतफेड नोंद नाही.')
          else
            ...sorted.map(
              (payment) => Card(
                color: Colors.white,
                child: ListTile(
                  leading: const Icon(
                    Icons.receipt_long,
                    color: Color(0xFF218838),
                  ),
                  title: Text(_money(payment.amount)),
                  subtitle: Text(
                    '${_formatDate(payment.paidOn)} • मूळधन ${_money(payment.principalPaid)}'
                    ' • व्याज ${_money(payment.interestPaid)}',
                  ),
                  trailing: _RepaymentActionsMenu(
                    onEdit: () => onEdit(payment),
                    onDelete: () => onDelete(payment),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CreateLoanDialog extends StatefulWidget {
  final LoanRepository repository;
  final List<Member> members;

  const _CreateLoanDialog({required this.repository, required this.members});

  @override
  State<_CreateLoanDialog> createState() => _CreateLoanDialogState();
}

class _CreateLoanDialogState extends State<_CreateLoanDialog> {
  final _formKey = GlobalKey<FormState>();
  final _principalController = TextEditingController();
  late String _memberId;
  DateTime _disbursedOn = DateTime.now();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _memberId = widget.members.first.id;
  }

  @override
  void dispose() {
    _principalController.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final today = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _disbursedOn.isAfter(today) ? today : _disbursedOn,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'कर्ज दिल्याची तारीख निवडा',
    );
    if (date != null) setState(() => _disbursedOn = date);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.createLoan(
        memberId: _memberId,
        principal: double.parse(_principalController.text.trim()),
        disbursedOn: _disbursedOn,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('नवीन कर्ज नोंद'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _memberId,
              decoration: const InputDecoration(labelText: 'सदस्य'),
              items: widget.members
                  .map(
                    (member) => DropdownMenuItem(
                      value: member.id,
                      child: Text(member.name),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _memberId = value);
                    },
            ),
            TextFormField(
              controller: _principalController,
              decoration: const InputDecoration(labelText: 'कर्जाची रक्कम (₹)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              validator: (value) {
                final amount = double.tryParse(value?.trim() ?? '');
                return amount == null || amount <= 0
                    ? 'योग्य कर्जाची रक्कम भरा.'
                    : null;
              },
            ),
            TextButton.icon(
              onPressed: _saving ? null : _chooseDate,
              icon: const Icon(Icons.calendar_month),
              label: Text('कर्ज दिनांक: ${_formatDate(_disbursedOn)}'),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('व्याज: बाकी मूळधनावर दरमहा 2%'),
            ),
            if (_error != null) _ErrorText(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('रद्द करा'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'जतन होत आहे...' : 'कर्ज नोंदवा'),
        ),
      ],
    );
  }
}

class _RepaymentDialog extends StatefulWidget {
  final LoanRepository repository;
  final LoanAccount loan;
  final LoanBalance balance;
  final DateTime earliestPaymentDate;
  final DateTime latestPaymentDate;
  final LoanRepayment? repaymentToEdit;

  const _RepaymentDialog({
    required this.repository,
    required this.loan,
    required this.balance,
    required this.earliestPaymentDate,
    required this.latestPaymentDate,
    this.repaymentToEdit,
  });

  @override
  State<_RepaymentDialog> createState() => _RepaymentDialogState();
}

class _RepaymentDialogState extends State<_RepaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _interestController = TextEditingController();
  final _principalController = TextEditingController();
  DateTime _paidOn = DateTime.now();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final repayment = widget.repaymentToEdit;
    _interestController.text =
        (repayment?.interestPaid ?? widget.balance.monthlyInterest)
            .toStringAsFixed(2);
    _principalController.text = (repayment?.principalPaid ?? 0).toStringAsFixed(
      2,
    );
    _paidOn = repayment?.paidOn ?? DateTime.now();
    final earliest = _dateOnly(widget.earliestPaymentDate);
    final latest = _dateOnly(widget.latestPaymentDate);
    if (_paidOn.isBefore(earliest)) _paidOn = earliest;
    if (_paidOn.isAfter(latest)) _paidOn = latest;
  }

  @override
  void dispose() {
    _interestController.dispose();
    _principalController.dispose();
    super.dispose();
  }

  double get _interestAmount =>
      double.tryParse(_interestController.text.trim()) ?? 0;

  double get _principalAmount =>
      double.tryParse(_principalController.text.trim()) ?? 0;

  double get _totalAmount => _interestAmount + _principalAmount;

  Future<void> _chooseDate() async {
    final latest = _dateOnly(widget.latestPaymentDate);
    final date = await showDatePicker(
      context: context,
      initialDate: _paidOn,
      firstDate: _dateOnly(widget.earliestPaymentDate),
      lastDate: latest,
      helpText: 'परतफेड तारीख निवडा',
    );
    if (date != null) setState(() => _paidOn = date);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repayment = widget.repaymentToEdit;
      if (repayment == null) {
        await widget.repository.recordRepayment(
          loanId: widget.loan.id,
          interestPaid: _interestAmount,
          principalPaid: _principalAmount,
          paidOn: _paidOn,
        );
      } else {
        await widget.repository.editRepayment(
          repaymentId: repayment.id,
          interestPaid: _interestAmount,
          principalPaid: _principalAmount,
          paidOn: _paidOn,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.repaymentToEdit == null ? 'परतफेड नोंद' : 'परतफेड दुरुस्त करा',
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('बाकी मूळधन: ${_money(widget.balance.principalRemaining)}'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _interestController,
                decoration: InputDecoration(
                  labelText: 'व्याज (मासिक 2%) (₹)',
                  helperText:
                      'बाकी मूळधनाच्या 2% प्रमाणे: ${_money(widget.balance.monthlyInterest)}',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                onChanged: (_) => setState(() {}),
                validator: _validateRepaymentAmount,
              ),
              TextFormField(
                controller: _principalController,
                decoration: InputDecoration(
                  labelText: 'मूळधन परतफेड रक्कम (₹)',
                  helperText:
                      'बाकी मूळधन: ${_money(widget.balance.principalRemaining)} (जास्त रक्कमही चालेल)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                onChanged: (_) => setState(() {}),
                validator: _validateRepaymentAmount,
              ),
              const SizedBox(height: 8),
              Text(
                'एकूण जमा: ${_money(_totalAmount)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: _saving ? null : _chooseDate,
                icon: const Icon(Icons.event),
                label: Text('परतफेड दिनांक: ${_formatDate(_paidOn)}'),
              ),
              if (_error != null) _ErrorText(_error!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('रद्द करा'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? 'जतन होत आहे...'
                : widget.repaymentToEdit == null
                ? 'परतफेड नोंदवा'
                : 'बदल जतन करा',
          ),
        ),
      ],
    );
  }
}

String? _validateRepaymentAmount(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final amount = double.tryParse(value.trim());
  if (amount == null || amount < 0) return 'योग्य रक्कम भरा.';
  return null;
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;

  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFFE0F2E4),
            child: Text('$count'),
          ),
        ],
      ),
    );
  }
}

class _EmptyLabel extends StatelessWidget {
  final String message;

  const _EmptyLabel({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Text(message, style: const TextStyle(color: Colors.black54)),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String message;

  const _ErrorText(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(message, style: const TextStyle(color: Colors.red)),
    );
  }
}

class _LoanTabIcon extends StatelessWidget {
  final IconData icon;
  final int tabIndex;

  const _LoanTabIcon({required this.icon, required this.tabIndex});

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) => Icon(
        icon,
        color: controller.index == tabIndex
            ? const Color(0xFF17652B)
            : Colors.white,
      ),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LoadFailure({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'कर्जाची माहिती लोड करता आली नाही.\n$message\n\n'
              'Supabase मध्ये loans.sql चालवले आहे का ते तपासा.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('पुन्हा प्रयत्न करा'),
            ),
          ],
        ),
      ),
    );
  }
}

String _money(double amount) {
  final rounded = (amount * 100).round() / 100;
  final wholeRupees = rounded == rounded.roundToDouble();
  return wholeRupees
      ? '₹${rounded.toStringAsFixed(0)}'
      : '₹${rounded.toStringAsFixed(2)}';
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}
