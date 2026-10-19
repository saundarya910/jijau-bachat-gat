import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/member_repository.dart';
import 'package:flutter_application_1/services/loan_repository.dart';
import 'package:flutter_application_1/loan_screens.dart';
import 'package:flutter_application_1/services/finance_repository.dart';
import 'package:flutter_application_1/finance_screens.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    runApp(const JijauApp());
    return;
  }

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  runApp(JijauApp(client: Supabase.instance.client));
}

class JijauApp extends StatelessWidget {
  final SupabaseClient? client;

  const JijauApp({super.key, this.client});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF218838);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'जिजाऊ महिला बचत गट',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: green, primary: green),
        scaffoldBackgroundColor: const Color(0xFFF4F8F4),
        appBarTheme: const AppBarTheme(
          backgroundColor: green,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
      ),
      home: client == null
          ? const SupabaseSetupScreen()
          : AuthGate(client: client!),
    );
  }
}

class SupabaseSetupScreen extends StatelessWidget {
  const SupabaseSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Supabase configuration is missing. Follow the setup steps in README.md.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  final SupabaseClient client;

  const AuthGate({super.key, required this.client});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  void _signedIn() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (widget.client.auth.currentSession == null) {
      return SignInScreen(client: widget.client, onSignedIn: _signedIn);
    }
    return HomeScreen(client: widget.client, onSignedOut: _signedIn);
  }
}

class SignInScreen extends StatefulWidget {
  final SupabaseClient client;
  final VoidCallback onSignedIn;

  const SignInScreen({
    super.key,
    required this.client,
    required this.onSignedIn,
  });

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _isSigningIn = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSigningIn = true;
      _error = null;
    });
    try {
      await widget.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) widget.onSignedIn();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('प्रशासक लॉगिन')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'ईमेल'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'ईमेल आवश्यक आहे.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'पासवर्ड'),
                    obscureText: true,
                    validator: (value) => value == null || value.isEmpty
                        ? 'पासवर्ड आवश्यक आहे.'
                        : null,
                    onFieldSubmitted: (_) => _signIn(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _isSigningIn ? null : _signIn,
                    child: Text(_isSigningIn ? 'प्रवेश करत आहे...' : 'लॉगिन'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final SupabaseClient client;
  final VoidCallback onSignedOut;

  const HomeScreen({
    super.key,
    required this.client,
    required this.onSignedOut,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MemberRepository _members;
  late final LoanRepository _loans;
  late final FinanceRepository _finance;

  @override
  void initState() {
    super.initState();
    _members = MemberRepository(widget.client);
    _loans = LoanRepository(widget.client);
    _finance = FinanceRepository(widget.client);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'जिजाऊ महिला बचत गट',
          style: TextStyle(fontWeight: .bold),
        ),
        actions: [
          IconButton(
            onPressed: () async {
              await widget.client.auth.signOut();
              widget.onSignedOut();
            },
            icon: const Icon(Icons.logout),
            tooltip: 'लॉगआउट',
          ),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('सूचना विभाग पुढे जोडला जाईल.')),
              );
            },
            icon: const Icon(Icons.notifications_none),
            tooltip: 'सूचना',
          ),
        ],
      ),
      body: StreamBuilder<int>(
        stream: _members.memberCount,
        builder: (context, snapshot) {
          final memberCountLabel = snapshot.hasData
              ? 'नोंदणीकृत सदस्य: ${snapshot.data}'
              : snapshot.hasError
              ? 'सदस्य संख्या उपलब्ध नाही'
              : 'सदस्य संख्या लोड होत आहे...';
          final memberCountValue = snapshot.hasData
              ? '${snapshot.data}'
              : snapshot.hasError
              ? '—'
              : '...';
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2E4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'आपले स्वागत आहे!',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF17652B),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'बचत, विश्वास आणि स्वावलंबन',
                        style: TextStyle(fontSize: 16),
                      ),
                      SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(Icons.groups, color: Color(0xFF218838)),
                          SizedBox(width: 8),
                          Text(
                            memberCountLabel,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'मुख्य माहिती',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SummaryCard(
                        title: 'मासिक बचत',
                        value: '₹500',
                        subtitle: 'प्रति सदस्य',
                        icon: Icons.savings_outlined,
                        color: Color(0xFF218838),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: SummaryCard(
                        title: 'एकूण सदस्य',
                        value: memberCountValue,
                        subtitle: snapshot.hasError
                            ? 'डेटाबेस त्रुटी'
                            : 'नोंदणीकृत',
                        icon: Icons.people_alt_outlined,
                        color: Color(0xFF1769AA),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text(
                  'व्यवस्थापन विभाग',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                MenuTile(
                  title: 'सदस्य नोंदणी',
                  subtitle: 'सर्व सदस्य पहा किंवा नवीन नोंदणी करा',
                  icon: Icons.people_alt_outlined,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          MemberListScreen(repository: _members),
                    ),
                  ),
                ),
                MenuTile(
                  title: 'मासिक बचत',
                  subtitle: 'महिन्यानुसार जमा व सदस्यांचा इतिहास',
                  icon: Icons.account_balance_wallet_outlined,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          MonthlySavingsScreen(repository: _members),
                    ),
                  ),
                ),
                MenuTile(
                  title: 'कर्ज व परतफेड',
                  subtitle: 'कर्ज खाते, व्याज व परतफेड नोंद',
                  icon: Icons.currency_rupee,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => LoanManagementScreen(
                        loans: _loans,
                        members: _members,
                      ),
                    ),
                  ),
                ),
                MenuTile(
                  title: 'रोख व UPI व्यवहार',
                  subtitle: 'जमा, खर्च आणि व्यवहार नोंद',
                  icon: Icons.receipt_long_outlined,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          FinanceTransactionsScreen(repository: _finance),
                    ),
                  ),
                ),
                MenuTile(
                  title: 'अहवाल',
                  subtitle: 'महिन्यानुसार बचत व कर्ज अहवाल',
                  icon: Icons.bar_chart,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => FinanceReportsScreen(
                        members: _members,
                        loans: _loans,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'टीप: सदस्य संख्या डेटाबेसमधून घेतली आहे. इतर आकडे नमुना आहेत.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class MemberListScreen extends StatefulWidget {
  final MemberRepository repository;

  const MemberListScreen({super.key, required this.repository});

  @override
  State<MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends State<MemberListScreen> {
  final _searchController = TextEditingController();
  final _speech = SpeechToText();
  late Future<List<Member>> _members;
  String _searchQuery = '';
  String? _voiceError;
  bool _isListening = false;
  bool _speechInitialized = false;

  @override
  void initState() {
    super.initState();
    _members = widget.repository.fetchMembers();
  }

  void _reloadMembers() {
    setState(() {
      _members = widget.repository.fetchMembers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_speechInitialized && !_speech.isNotListening) {
      _speech.stop();
    }
    super.dispose();
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() {
      _searchController.value = TextEditingValue(
        text: result.recognizedWords,
        selection: TextSelection.collapsed(
          offset: result.recognizedWords.length,
        ),
      );
      _searchQuery = result.recognizedWords;
      _voiceError = null;
    });
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    setState(() => _isListening = status == 'listening');
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _voiceError = error.errorMsg;
    });
  }

  Future<void> _toggleVoiceSearch() async {
    setState(() => _voiceError = null);
    try {
      if (_isListening) {
        await _speech.stop();
        if (mounted) setState(() => _isListening = false);
        return;
      }

      final available =
          _speechInitialized ||
          await _speech.initialize(
            onStatus: _onSpeechStatus,
            onError: _onSpeechError,
          );
      _speechInitialized = available;
      if (!available) {
        if (mounted) {
          setState(() {
            _voiceError = 'या ब्राउझरमध्ये आवाज शोध उपलब्ध नाही. Chrome मध्ये परवानगी द्या.';
          });
        }
        return;
      }

      final locales = await _speech.locales();
      final marathiLocale = locales
          .where(
            (locale) => locale.localeId
                .toLowerCase()
                .replaceAll('_', '-')
                .startsWith('mr'),
          )
          .firstOrNull
          ?.localeId;
      await _speech.listen(
        onResult: _onSpeechResult,
        listenOptions: SpeechListenOptions(
          localeId: marathiLocale ?? 'mr-IN',
          listenMode: ListenMode.search,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
        ),
      );
      if (mounted) setState(() => _isListening = true);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _voiceError = error.toString();
        });
      }
    }
  }

  Future<void> _registerMember() async {
    final registered = await showDialog<bool>(
      context: context,
      builder: (context) =>
          MemberRegistrationDialog(repository: widget.repository),
    );
    if (registered == true && mounted) {
      _reloadMembers();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('सदस्याची नोंद यशस्वी झाली.')),
      );
    }
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'नाव किंवा मोबाइल क्रमांक शोधा',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchQuery.isNotEmpty)
                IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _voiceError = null;
                    });
                  },
                  icon: const Icon(Icons.clear),
                  tooltip: 'शोध पुसून टाका',
                ),
              IconButton(
                onPressed: _toggleVoiceSearch,
                icon: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: _isListening ? Colors.red : null,
                ),
                tooltip: _isListening ? 'आवाज शोध थांबवा' : 'आवाजाने शोधा',
              ),
            ],
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildFilteredMemberList(List<Member> members) {
    final query = _searchQuery.trim().toLowerCase();
    final filteredMembers = members.where((member) {
      return member.name.toLowerCase().contains(query) ||
          (member.phone?.toLowerCase().contains(query) ?? false);
    }).toList();
    if (filteredMembers.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty
              ? 'अजून कोणत्याही सदस्याची नोंद केलेली नाही.'
              : 'या शोधासाठी सदस्य सापडला नाही.',
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: filteredMembers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final member = filteredMembers[index];
        return Card(
          color: Colors.white,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFE0F2E4),
              child: Text(
                member.name.trim().isEmpty
                    ? '?'
                    : member.name.trim().characters.first.toUpperCase(),
                style: const TextStyle(color: Color(0xFF218838)),
              ),
            ),
            title: Text(member.name),
            subtitle: Text(
              [
                if (member.phone?.isNotEmpty == true) member.phone!,
                'नोंदणी: ${_formatDate(member.createdAt)}',
              ].join('\n'),
            ),
            isThreeLine: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => MemberSavingsHistoryScreen(
                  repository: widget.repository,
                  member: member,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('नोंदणीकृत सदस्य'),
        actions: [
          IconButton(
            onPressed: _reloadMembers,
            icon: const Icon(Icons.refresh),
            tooltip: 'सदस्य यादी रिफ्रेश करा',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _registerMember,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('सदस्य नोंदणी'),
      ),
      body: FutureBuilder<List<Member>>(
        future: _members,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'सदस्यांची माहिती लोड करता आली नाही.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _reloadMembers,
                      icon: const Icon(Icons.refresh),
                      label: const Text('पुन्हा प्रयत्न करा'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('सदस्यांची माहिती आणत आहे...'),
                ],
              ),
            );
          }

          final members = snapshot.data!;
          return Column(
            children: [
              _buildSearchField(),
              if (_voiceError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'आवाज शोध: $_voiceError',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _reloadMembers(),
                  child: _buildFilteredMemberList(members),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    final date = dateTime.toLocal();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}

class MonthlySavingsScreen extends StatefulWidget {
  final MemberRepository repository;

  const MonthlySavingsScreen({super.key, required this.repository});

  @override
  State<MonthlySavingsScreen> createState() => _MonthlySavingsScreenState();
}

class _MonthlySavingsScreenState extends State<MonthlySavingsScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<SavingsOverview> _overview;
  final _searchController = TextEditingController();
  final _speech = SpeechToText();
  String _searchQuery = '';
  String? _voiceError;
  bool _isListening = false;
  bool _speechInitialized = false;

  @override
  void initState() {
    super.initState();
    _overview = widget.repository.fetchSavingsOverview();
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_speechInitialized && !_speech.isNotListening) {
      _speech.stop();
    }
    super.dispose();
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() {
      _searchController.value = TextEditingValue(
        text: result.recognizedWords,
        selection: TextSelection.collapsed(
          offset: result.recognizedWords.length,
        ),
      );
      _searchQuery = result.recognizedWords;
      _voiceError = null;
    });
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    setState(() => _isListening = status == 'listening');
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _voiceError = error.errorMsg;
    });
  }

  Future<void> _toggleVoiceSearch() async {
    setState(() => _voiceError = null);
    try {
      if (_isListening) {
        await _speech.stop();
        if (mounted) setState(() => _isListening = false);
        return;
      }

      final available =
          _speechInitialized ||
          await _speech.initialize(
            onStatus: _onSpeechStatus,
            onError: _onSpeechError,
          );
      _speechInitialized = available;
      if (!available) {
        if (mounted) {
          setState(() {
            _voiceError = 'या ब्राउझरमध्ये आवाज शोध उपलब्ध नाही. Chrome मध्ये परवानगी द्या.';
          });
        }
        return;
      }

      final locales = await _speech.locales();
      final marathiLocale = locales
          .where(
            (locale) => locale.localeId
                .toLowerCase()
                .replaceAll('_', '-')
                .startsWith('mr'),
          )
          .firstOrNull
          ?.localeId;
      await _speech.listen(
        onResult: _onSpeechResult,
        listenOptions: SpeechListenOptions(
          localeId: marathiLocale ?? 'mr-IN',
          listenMode: ListenMode.search,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
        ),
      );
      if (mounted) setState(() => _isListening = true);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _voiceError = error.toString();
        });
      }
    }
  }

  Widget _buildSavingsSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'नाव किंवा मोबाइल क्रमांक शोधा',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchQuery.isNotEmpty)
                IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _voiceError = null;
                    });
                  },
                  icon: const Icon(Icons.clear),
                  tooltip: 'शोध पुसून टाका',
                ),
              IconButton(
                onPressed: _toggleVoiceSearch,
                icon: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: _isListening ? Colors.red : null,
                ),
                tooltip: _isListening ? 'आवाज शोध थांबवा' : 'आवाजाने शोधा',
              ),
            ],
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  void _reload() {
    setState(() {
      _overview = widget.repository.fetchSavingsOverview();
    });
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + offset,
      );
    });
  }

  Future<void> _chooseMonth() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'बचतीचा महिना निवडा',
    );
    if (selected != null) {
      setState(() {
        _selectedMonth = DateTime(selected.year, selected.month);
      });
    }
  }

  Future<void> _recordPayment(Member member) async {
    final recorded = await showDialog<bool>(
      context: context,
      builder: (context) => SavingsPaymentDialog(
        repository: widget.repository,
        member: member,
        contributionMonth: _selectedMonth,
      ),
    );
    if (recorded == true && mounted) {
      _reload();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('मासिक बचत नोंदवली.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('मासिक बचत'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'माहिती रिफ्रेश करा',
          ),
        ],
      ),
      body: FutureBuilder<SavingsOverview>(
        future: _overview,
        builder: (context, memberSnapshot) {
          if (memberSnapshot.hasError) {
            return _SavingsLoadError(
              message: '${memberSnapshot.error}',
              onRetry: _reload,
            );
          }
          if (!memberSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final overview = memberSnapshot.data!;
          final members = overview.members;
          final monthPayments = overview.payments
              .where(
                (payment) =>
                    payment.contributionMonth.year == _selectedMonth.year &&
                    payment.contributionMonth.month == _selectedMonth.month,
              )
              .toList();
          final paidByMember = {
            for (final payment in monthPayments) payment.memberId: payment,
          };
          final query = _searchQuery.trim().toLowerCase();
          final filteredMembers = members.where((member) {
            return member.name.toLowerCase().contains(query) ||
                (member.phone?.toLowerCase().contains(query) ?? false);
          }).toList();
          final unpaidMembers = filteredMembers
              .where((member) => !paidByMember.containsKey(member.id))
              .toList();
          final paidMembers = filteredMembers
              .where((member) => paidByMember.containsKey(member.id))
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'मागील महिना',
                    ),
                    TextButton.icon(
                      onPressed: _chooseMonth,
                      icon: const Icon(Icons.calendar_month),
                      label: Text(_monthLabel(_selectedMonth)),
                    ),
                    IconButton(
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'पुढील महिना',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${paidByMember.length} / ${members.length} सदस्यांनी भरले'
                    '  •  जमा ₹${paidByMember.length * 500}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              _buildSavingsSearchField(),
              if (_voiceError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'आवाज शोध: $_voiceError',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              Expanded(
                child: filteredMembers.isEmpty
                    ? Center(
                        child: Text(
                          members.isEmpty
                              ? 'सदस्यांची नोंद नाही.'
                              : 'या शोधासाठी सदस्य सापडला नाही.',
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          _SavingsSectionHeading(
                            title: 'ज्यांनी बचत भरलेली नाही',
                            count: unpaidMembers.length,
                            color: Colors.orange.shade800,
                          ),
                          if (unpaidMembers.isEmpty)
                            const _SavingsSectionEmpty(
                              message: 'या महिन्यात बाकी सदस्य नाहीत.',
                            )
                          else
                            ...unpaidMembers.map(
                              (member) => _buildSavingsMemberTile(
                                member,
                                paidByMember[member.id],
                              ),
                            ),
                          const SizedBox(height: 12),
                          _SavingsSectionHeading(
                            title: 'ज्यांनी बचत भरली आहे',
                            count: paidMembers.length,
                            color: const Color(0xFF218838),
                          ),
                          if (paidMembers.isEmpty)
                            const _SavingsSectionEmpty(
                              message: 'या महिन्यात बचत भरलेला सदस्य नाही.',
                            )
                          else
                            ...paidMembers.map(
                              (member) => _buildSavingsMemberTile(
                                member,
                                paidByMember[member.id],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSavingsMemberTile(Member member, SavingsPayment? payment) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => MemberSavingsHistoryScreen(
              repository: widget.repository,
              member: member,
            ),
          ),
        ),
        leading: Icon(
          payment == null ? Icons.pending_actions : Icons.check_circle,
          color: payment == null ? Colors.orange : const Color(0xFF218838),
        ),
        title: Text(member.name),
        subtitle: Text(
          payment == null
              ? 'बाकी • ₹500'
              : 'भरले • ${_formatDate(payment.paidOn)} • ₹${payment.amount}',
        ),
        trailing: payment == null
            ? IconButton(
                onPressed: () => _recordPayment(member),
                icon: const Icon(Icons.add_card, color: Color(0xFF218838)),
                tooltip: 'बचत जमा नोंदवा',
              )
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _SavingsSectionHeading extends StatelessWidget {
  final String title;
  final int count;
  final Color color;

  const _SavingsSectionHeading({
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavingsSectionEmpty extends StatelessWidget {
  final String message;

  const _SavingsSectionEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Text(message, style: const TextStyle(color: Colors.black54)),
    );
  }
}

class MemberSavingsHistoryScreen extends StatefulWidget {
  final MemberRepository repository;
  final Member member;

  const MemberSavingsHistoryScreen({
    super.key,
    required this.repository,
    required this.member,
  });

  @override
  State<MemberSavingsHistoryScreen> createState() =>
      _MemberSavingsHistoryScreenState();
}

class _MemberSavingsHistoryScreenState
    extends State<MemberSavingsHistoryScreen> {
  late Future<List<SavingsPayment>> _history;

  @override
  void initState() {
    super.initState();
    _history = widget.repository.fetchPaymentHistory(widget.member.id);
  }

  void _reload() {
    setState(() {
      _history = widget.repository.fetchPaymentHistory(widget.member.id);
    });
  }

  Future<void> _recordPayment() async {
    final recorded = await showDialog<bool>(
      context: context,
      builder: (context) => SavingsPaymentDialog(
        repository: widget.repository,
        member: widget.member,
        contributionMonth: DateTime(DateTime.now().year, DateTime.now().month),
      ),
    );
    if (recorded == true && mounted) {
      _reload();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('मासिक बचत नोंदवली.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.member.name),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'इतिहास रिफ्रेश करा',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _recordPayment,
        icon: const Icon(Icons.add_card),
        label: const Text('बचत नोंदवा'),
      ),
      body: FutureBuilder<List<SavingsPayment>>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _SavingsLoadError(
              message: '${snapshot.error}',
              onRetry: _reload,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final payments = snapshot.data!;
          if (payments.isEmpty) {
            return const Center(
              child: Text('या सदस्याची बचत जमा नोंद अजून केलेली नाही.'),
            );
          }
          final total = payments.fold<int>(
            0,
            (sum, payment) => sum + payment.amount,
          );
          return Column(
            children: [
              ListTile(
                title: const Text('एकूण जमा बचत'),
                trailing: Text(
                  '₹$total',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF218838),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: payments.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final payment = payments[index];
                    return Card(
                      color: Colors.white,
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFE0F2E4),
                          child: Icon(
                            Icons.savings_outlined,
                            color: Color(0xFF218838),
                          ),
                        ),
                        title: Text(
                          '${_monthLabel(payment.contributionMonth)} • ₹${payment.amount}',
                        ),
                        subtitle: Text(
                          'जमा दिनांक: ${_formatDate(payment.paidOn)}',
                        ),
                        trailing: const Icon(
                          Icons.check_circle,
                          color: Color(0xFF218838),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SavingsPaymentDialog extends StatefulWidget {
  final MemberRepository repository;
  final Member member;
  final DateTime contributionMonth;

  const SavingsPaymentDialog({
    super.key,
    required this.repository,
    required this.member,
    required this.contributionMonth,
  });

  @override
  State<SavingsPaymentDialog> createState() => _SavingsPaymentDialogState();
}

class _SavingsPaymentDialogState extends State<SavingsPaymentDialog> {
  late DateTime _contributionMonth;
  DateTime _paidOn = DateTime.now();
  String? _error;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _contributionMonth = DateTime(
      widget.contributionMonth.year,
      widget.contributionMonth.month,
    );
  }

  Future<void> _chooseContributionMonth() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _contributionMonth,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'बचतीचा महिना निवडा',
    );
    if (selected != null) {
      setState(() {
        _contributionMonth = DateTime(selected.year, selected.month);
      });
    }
  }

  Future<void> _choosePaidDate() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _paidOn.isAfter(today) ? today : _paidOn,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'पैसे मिळाल्याची तारीख निवडा',
    );
    if (selected != null) setState(() => _paidOn = selected);
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.repository.recordSavingsPayment(
        memberId: widget.member.id,
        contributionMonth: _contributionMonth,
        paidOn: _paidOn,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.code == '23505'
              ? 'या महिन्याची बचत आधीच नोंदवली आहे.'
              : error.message;
        });
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('मासिक बचत नोंद'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.member.name),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _chooseContributionMonth,
            icon: const Icon(Icons.calendar_month),
            label: Text('बचतीचा महिना: ${_monthLabel(_contributionMonth)}'),
          ),
          TextButton.icon(
            onPressed: _choosePaidDate,
            icon: const Icon(Icons.event),
            label: Text('पैसे मिळाले: ${_formatDate(_paidOn)}'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('रक्कम: ₹500'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('रद्द करा'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? 'जतन होत आहे...' : 'जमा नोंदवा'),
        ),
      ],
    );
  }
}

class _SavingsLoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _SavingsLoadError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'बचतीची माहिती लोड करता आली नाही.\n$message\n\n'
              'तपासा की Supabase मध्ये monthly_savings migration चालवली आहे.',
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

String _monthLabel(DateTime date) {
  const months = [
    'जानेवारी',
    'फेब्रुवारी',
    'मार्च',
    'एप्रिल',
    'मे',
    'जून',
    'जुलै',
    'ऑगस्ट',
    'सप्टेंबर',
    'ऑक्टोबर',
    'नोव्हेंबर',
    'डिसेंबर',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

String _formatDate(DateTime dateTime) {
  final date = dateTime.toLocal();
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

class MemberRegistrationDialog extends StatefulWidget {
  final MemberRepository repository;

  const MemberRegistrationDialog({super.key, required this.repository});

  @override
  State<MemberRegistrationDialog> createState() =>
      _MemberRegistrationDialogState();
}

class _MemberRegistrationDialogState extends State<MemberRegistrationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _error;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.repository.addMember(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('सदस्य नोंदणी'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'सदस्याचे नाव'),
              textCapitalization: TextCapitalization.words,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'नाव आवश्यक आहे.'
                  : null,
            ),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'मोबाइल क्रमांक'),
              keyboardType: TextInputType.phone,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('रद्द करा'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? 'जतन होत आहे...' : 'जतन करा'),
        ),
      ],
    );
  }
}

void showMessage(BuildContext context, String section) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('$section विभाग पुढे तयार करू.')));
}

class SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const SummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(subtitle, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class MenuTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const MenuTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE0F2E4),
          child: Icon(icon, color: const Color(0xFF218838)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
