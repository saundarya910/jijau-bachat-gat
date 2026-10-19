import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/finance/finance_shared_widgets.dart';
import 'package:flutter_application_1/services/finance_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FinanceTransactionsScreen extends StatefulWidget {
  final FinanceRepository repository;

  const FinanceTransactionsScreen({super.key, required this.repository});

  @override
  State<FinanceTransactionsScreen> createState() =>
      _FinanceTransactionsScreenState();
}

class _FinanceTransactionsScreenState
    extends State<FinanceTransactionsScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<List<FinanceTransaction>> _transactions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _transactions = widget.repository.fetchTransactions(_selectedMonth);
  }

  void _reload() => setState(_load);

  void _changeMonth(int offset) {
    final month = DateTime(_selectedMonth.year, _selectedMonth.month + offset);
    final now = DateTime.now();
    if (month.isAfter(DateTime(now.year, now.month))) return;

    setState(() {
      _selectedMonth = month;
      _load();
    });
  }

  Future<void> _addTransaction() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _FinanceTransactionDialog(
        repository: widget.repository,
        initialDate: _selectedMonth,
      ),
    );
    if (saved != true || !mounted) return;

    _reload();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('व्यवहार नोंदवला.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1FAE5A),
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'मागे जा',
        ),
        title: const Text(
          'रोख व UPI व्यवहार',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'रिफ्रेश करा',
          ),
        ],
      ),
      body: FutureBuilder<List<FinanceTransaction>>(
        future: _transactions,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FinanceLoadError(
              message: '${snapshot.error}',
              onRetry: _reload,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final transactions = snapshot.data!;
          final deposits = sumByType(
            transactions,
            FinanceTransactionType.deposit,
          );
          final expenses = sumByType(
            transactions,
            FinanceTransactionType.expense,
          );
          final cashTotal = sumByMethod(
            transactions,
            FinancePaymentMethod.cash,
          );
          final upiTotal = sumByMethod(
            transactions,
            FinancePaymentMethod.upi,
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
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FinanceMetric(
                    label: 'एकूण जमा',
                    amount: deposits,
                    icon: Icons.south_west,
                    color: const Color(0xFF218838),
                  ),
                  FinanceMetric(
                    label: 'एकूण खर्च',
                    amount: expenses,
                    icon: Icons.north_east,
                    color: const Color(0xFFC62828),
                  ),
                  FinanceMetric(
                    label: 'रोख व्यवहार',
                    amount: cashTotal,
                    icon: Icons.payments_outlined,
                    color: const Color(0xFF1769AA),
                  ),
                  FinanceMetric(
                    label: 'UPI व्यवहार',
                    amount: upiTotal,
                    icon: Icons.phone_android,
                    color: const Color(0xFF6A1B9A),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'व्यवहार (${transactions.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (transactions.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: Text('या महिन्यात कोणताही व्यवहार नोंदवलेला नाही.'),
                    ),
                  ),
                )
              else
                ...transactions.map(
                  (transaction) =>
                      FinanceTransactionTile(transaction: transaction),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTransaction,
        icon: const Icon(Icons.add),
        label: const Text('नवीन व्यवहार'),
      ),
    );
  }
}

class _FinanceTransactionDialog extends StatefulWidget {
  final FinanceRepository repository;
  final DateTime initialDate;

  const _FinanceTransactionDialog({
    required this.repository,
    required this.initialDate,
  });

  @override
  State<_FinanceTransactionDialog> createState() =>
      _FinanceTransactionDialogState();
}

class _FinanceTransactionDialogState extends State<_FinanceTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  FinanceTransactionType _type = FinanceTransactionType.deposit;
  FinancePaymentMethod _method = FinancePaymentMethod.cash;
  late DateTime _date;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    final selected = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      1,
    );
    _date = selected.isAfter(today) ? today : selected;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final today = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'व्यवहाराची तारीख निवडा',
    );
    if (date != null) setState(() => _date = date);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.addTransaction(
        type: _type,
        paymentMethod: _method,
        amount: double.parse(_amountController.text.trim()),
        transactionDate: _date,
        description: _descriptionController.text,
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
      title: const Text('नवीन व्यवहार नोंद'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('व्यवहाराचा प्रकार'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('जमा'),
                      selected: _type == FinanceTransactionType.deposit,
                      onSelected: _saving
                          ? null
                          : (_) => setState(
                              () => _type = FinanceTransactionType.deposit,
                            ),
                    ),
                    ChoiceChip(
                      label: const Text('खर्च'),
                      selected: _type == FinanceTransactionType.expense,
                      onSelected: _saving
                          ? null
                          : (_) => setState(
                              () => _type = FinanceTransactionType.expense,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('पैसे मिळण्याची / देण्याची पद्धत'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      avatar: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('रोख'),
                      selected: _method == FinancePaymentMethod.cash,
                      onSelected: _saving
                          ? null
                          : (_) => setState(
                              () => _method = FinancePaymentMethod.cash,
                            ),
                    ),
                    ChoiceChip(
                      avatar: const Icon(Icons.phone_android, size: 18),
                      label: const Text('UPI'),
                      selected: _method == FinancePaymentMethod.upi,
                      onSelected: _saving
                          ? null
                          : (_) => setState(
                              () => _method = FinancePaymentMethod.upi,
                            ),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'रक्कम (₹)',
                    prefixIcon: Icon(Icons.currency_rupee),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  validator: (value) {
                    final amount = double.tryParse(value?.trim() ?? '');
                    return amount == null || amount <= 0
                        ? 'योग्य रक्कम भरा.'
                        : null;
                  },
                ),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'तपशील (ऐच्छिक)',
                    prefixIcon: Icon(Icons.notes),
                  ),
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                ),
                TextButton.icon(
                  onPressed: _saving ? null : _chooseDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text('तारीख: ${formatDate(_date)}'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
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
          child: Text(_saving ? 'जतन होत आहे...' : 'नोंदवा'),
        ),
      ],
    );
  }
}
