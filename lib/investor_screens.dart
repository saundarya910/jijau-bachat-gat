import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/finance/finance_shared_widgets.dart';
import 'package:flutter_application_1/services/finance_repository.dart';
import 'package:flutter_application_1/services/investor_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InvestorManagementScreen extends StatefulWidget {
  final InvestorRepository repository;

  const InvestorManagementScreen({super.key, required this.repository});

  @override
  State<InvestorManagementScreen> createState() =>
      _InvestorManagementScreenState();
}

class _InvestorManagementScreenState extends State<InvestorManagementScreen> {
  late Future<InvestorOverview> _overview;

  @override
  void initState() {
    super.initState();
    _overview = widget.repository.fetchOverview();
  }

  Future<void> _reload() async {
    final request = widget.repository.fetchOverview();
    setState(() => _overview = request);
    await request;
  }

  Future<void> _addContribution() async {
    late InvestorOverview overview;
    try {
      overview = await _overview;
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('गुंतवणूकदार माहिती मिळाली नाही: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _InvestorContributionDialog(
        repository: widget.repository,
        balances: overview.balances,
      ),
    );
    if (saved == true && mounted) {
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('गुंतवणूक जमा नोंदवली.')));
      }
    }
  }

  Future<void> _recordPayout(InvestorBalance investor) async {
    final paid = await showDialog<bool>(
      context: context,
      builder: (context) => _InvestorPayoutDialog(
        repository: widget.repository,
        investor: investor,
      ),
    );
    if (paid == true && mounted) {
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('गुंतवणूकदाराचा परतावा नोंदवला.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('गुंतवणूकदार खाते'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'माहिती रिफ्रेश करा',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContribution,
        icon: const Icon(Icons.add),
        label: const Text('गुंतवणूक जमा'),
      ),
      body: FutureBuilder<InvestorOverview>(
        future: _overview,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('गुंतवणूकदार माहिती लोड करता आली नाही.'),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('पुन्हा प्रयत्न करा'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final overview = snapshot.data!;
          final totalPrincipal = overview.balances.fold<double>(
            0,
            (sum, item) => sum + item.principalRemaining,
          );
          final totalInterest = overview.balances.fold<double>(
            0,
            (sum, item) => sum + item.interestDue,
          );
          final investorsById = {
            for (final balance in overview.balances)
              balance.investorId: balance.name,
          };

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              Card(
                color: const Color(0xFFE0F2E4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'गुंतवणूकदारांना देय',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('मूळ रक्कम बाकी: ${_money(totalPrincipal)}'),
                      Text(
                        'गुंतवणूकदारांना द्यायचे व्याज: '
                        '${_money(totalInterest)}',
                      ),
                      Text(
                        'एकूण देय: ${_money(totalPrincipal + totalInterest)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'गुंतवणूकदारांना 2% मासिक व्याज द्यायचे आहे. '
                        'गुंतवणूकदारांनी मागणी केल्यावरच प्रत्यक्ष परतावा '
                        'नोंदवा. न दिलेले व्याज दरमहा वाढत राहते.',
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'व्याज प्रत्येक योगदानानंतरच्या महिन्याच्या '
                        'पहिल्या तारखेपासून मोजले जाते.',
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'सदस्यांच्या कर्ज परतफेडीमुळे गुंतवणूकदाराची बाकी '
                        'आपोआप कमी होत नाही. परतावा नोंदवताना दिलेले व्याज '
                        'आणि मूळ रक्कम वेगळी भरा.',
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'गुंतवणूक खाते कर्ज वितरणापासून स्वतंत्र आहे; '
                        'कर्ज रक्कम गुंतवणूक शिल्लकीने मर्यादित होत नाही.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _SectionTitle(
                title: 'गुंतवणूकदार',
                count: overview.balances.length,
              ),
              if (overview.balances.isEmpty)
                const _EmptyLabel(message: 'अजून गुंतवणूकदार नोंदलेले नाहीत.')
              else
                ...overview.balances.map(
                  (balance) => Card(
                    color: Colors.white,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE0F2E4),
                            child: Icon(
                              Icons.person_outline,
                              color: Color(0xFF218838),
                            ),
                          ),
                          title: Text(balance.name),
                          subtitle: Text(
                            'मूळ रक्कम बाकी ${_money(balance.principalRemaining)}'
                            ' • द्यायचे व्याज ${_money(balance.interestDue)}',
                          ),
                          isThreeLine: true,
                          trailing: Text(
                            _money(
                              balance.principalRemaining + balance.interestDue,
                            ),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (balance.principalRemaining + balance.interestDue >
                            0)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _recordPayout(balance),
                              icon: const Icon(Icons.outgoing_mail),
                              label: const Text('गुंतवणूकदाराला परतावा द्या'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              _SectionTitle(
                title: 'गुंतवणूक जमा व प्रत्यक्ष परतावा इतिहास',
                count: overview.transactions.length,
              ),
              if (overview.transactions.isEmpty)
                const _EmptyLabel(message: 'अजून व्यवहार नोंदवलेले नाहीत.')
              else
                ...overview.transactions.map((transaction) {
                  final typeLabel = switch (transaction.type) {
                    InvestorTransactionType.contribution => 'गुंतवणूक जमा',
                    InvestorTransactionType.interestPayout =>
                      'गुंतवणूकदाराला व्याज दिले',
                    InvestorTransactionType.principalPayout =>
                      'गुंतवणूकदाराला मूळ रक्कम दिली',
                  };
                  final methodContext =
                      transaction.type == InvestorTransactionType.contribution
                      ? 'जमा'
                      : 'परतावा';
                  return Card(
                    color: Colors.white,
                    child: ListTile(
                      leading: Icon(
                        transaction.type == InvestorTransactionType.contribution
                            ? Icons.south_west
                            : Icons.call_received,
                        color: const Color(0xFF218838),
                      ),
                      title: Text(
                        '${investorsById[transaction.investorId] ?? 'गुंतवणूकदार'}'
                        ' • ${_money(transaction.amount)}',
                      ),
                      subtitle: Text(
                        '$typeLabel • ${_formatDate(transaction.transactionDate)}'
                        ' • $methodContext: '
                        '${financePaymentMethodLabel(transaction.paymentMethod)}',
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _InvestorContributionDialog extends StatefulWidget {
  final InvestorRepository repository;
  final List<InvestorBalance> balances;

  const _InvestorContributionDialog({
    required this.repository,
    required this.balances,
  });

  @override
  State<_InvestorContributionDialog> createState() =>
      _InvestorContributionDialogState();
}

class _InvestorContributionDialogState
    extends State<_InvestorContributionDialog> {
  static const _newInvestorValue = '__new_investor__';
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  String _investorSelection = _newInvestorValue;
  String? get _investorId =>
      _investorSelection == _newInvestorValue ? null : _investorSelection;
  DateTime _transactionDate = DateTime.now();
  FinancePaymentMethod _paymentMethod = FinancePaymentMethod.cash;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final today = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _transactionDate.isAfter(today) ? today : _transactionDate,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'गुंतवणूक जमा तारीख निवडा',
    );
    if (date != null) setState(() => _transactionDate = date);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.addContribution(
        investorId: _investorId,
        investorName: _investorId == null ? _nameController.text.trim() : null,
        amount: double.parse(_amountController.text.trim()),
        transactionDate: _transactionDate,
        paymentMethod: _paymentMethod,
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
      title: const Text('गुंतवणूक जमा नोंद'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _investorSelection,
                decoration: const InputDecoration(labelText: 'गुंतवणूकदार'),
                items: [
                  const DropdownMenuItem<String>(
                    value: _newInvestorValue,
                    child: Text('नवीन गुंतवणूकदार'),
                  ),
                  ...widget.balances.map(
                    (investor) => DropdownMenuItem<String>(
                      value: investor.investorId,
                      child: Text(investor.name),
                    ),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _investorSelection = value);
                        }
                      },
              ),
              if (_investorId == null)
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'गुंतवणूकदाराचे नाव',
                  ),
                  validator: (value) =>
                      _investorId == null &&
                          (value == null || value.trim().isEmpty)
                      ? 'नाव आवश्यक आहे.'
                      : null,
                ),
              if (_investorId == null)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'हे नाव आधीपासून असल्यास रक्कम त्याच गुंतवणूकदाराच्या '
                    'खात्यात जमा होईल.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'गुंतवणुकीची रक्कम (₹)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (value) {
                  final amount = double.tryParse(value?.trim() ?? '');
                  return amount == null || amount <= 0
                      ? 'योग्य रक्कम भरा.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('रक्कम कशी जमा झाली?'),
              ),
              const SizedBox(height: 6),
              PaymentMethodSelector(
                value: _paymentMethod,
                onChanged: (method) => setState(() => _paymentMethod = method),
              ),
              TextButton.icon(
                onPressed: _saving ? null : _chooseDate,
                icon: const Icon(Icons.calendar_month),
                label: Text('जमा तारीख: ${_formatDate(_transactionDate)}'),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '2% साधे मासिक व्याज पुढील महिन्याच्या पहिल्या '
                  'तारखेपासून मोजले जाईल.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
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
          child: Text(_saving ? 'जतन होत आहे...' : 'जमा नोंदवा'),
        ),
      ],
    );
  }
}

class _InvestorPayoutDialog extends StatefulWidget {
  final InvestorRepository repository;
  final InvestorBalance investor;

  const _InvestorPayoutDialog({
    required this.repository,
    required this.investor,
  });

  @override
  State<_InvestorPayoutDialog> createState() => _InvestorPayoutDialogState();
}

class _InvestorPayoutDialogState extends State<_InvestorPayoutDialog> {
  final _formKey = GlobalKey<FormState>();
  final _interestController = TextEditingController(text: '0');
  final _principalController = TextEditingController(text: '0');
  DateTime _paidOn = DateTime.now();
  FinancePaymentMethod _paymentMethod = FinancePaymentMethod.cash;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _interestController.dispose();
    _principalController.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final today = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _paidOn.isAfter(today) ? today : _paidOn,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'परतावा दिल्याची तारीख निवडा',
    );
    if (date != null) setState(() => _paidOn = date);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final interestAmount = double.parse(_interestController.text.trim());
    final principalAmount = double.parse(_principalController.text.trim());
    if (interestAmount + principalAmount <= 0) {
      setState(() => _error = 'व्याज किंवा मूळ रकमेचा परतावा भरा.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.recordPayout(
        investorId: widget.investor.investorId,
        interestAmount: interestAmount,
        principalAmount: principalAmount,
        paidOn: _paidOn,
        paymentMethod: _paymentMethod,
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

  String? _validateAmount(String? value, double maximum, String label) {
    final amount = double.tryParse(value?.trim() ?? '');
    if (amount == null || amount < 0) {
      return 'योग्य $label रक्कम भरा.';
    }
    if (amount > maximum) {
      return 'रक्कम ${_money(maximum)} पेक्षा जास्त असू शकत नाही.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.investor.name} यांना परतावा'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('द्यायचे व्याज: ${_money(widget.investor.interestDue)}'),
              Text(
                'मूळ रक्कम बाकी: '
                '${_money(widget.investor.principalRemaining)}',
              ),
              TextFormField(
                controller: _interestController,
                decoration: const InputDecoration(
                  labelText: 'दिलेल्या व्याजाची रक्कम (₹)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (value) => _validateAmount(
                  value,
                  widget.investor.interestDue,
                  'व्याजाची',
                ),
              ),
              TextFormField(
                controller: _principalController,
                decoration: const InputDecoration(
                  labelText: 'परत दिलेल्या मूळ रकमेची रक्कम (₹)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (value) => _validateAmount(
                  value,
                  widget.investor.principalRemaining,
                  'मूळ रकमेची',
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('प्रत्यक्ष परतावा कशाने दिला?'),
              ),
              const SizedBox(height: 6),
              PaymentMethodSelector(
                value: _paymentMethod,
                onChanged: (method) => setState(() => _paymentMethod = method),
              ),
              TextButton.icon(
                onPressed: _saving ? null : _chooseDate,
                icon: const Icon(Icons.calendar_month),
                label: Text('परतावा तारीख: ${_formatDate(_paidOn)}'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
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
          child: Text(_saving ? 'जतन होत आहे...' : 'परतावा नोंदवा'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;

  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          CircleAvatar(
            radius: 15,
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
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(message, textAlign: TextAlign.center),
    );
  }
}

String _money(num amount) => '₹${amount.toStringAsFixed(2)}';

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';
