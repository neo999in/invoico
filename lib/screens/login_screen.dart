import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dashboard_screen.dart';
import '../database_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isRegistered = false;
  bool _isLoading = true;

  final _nameCtrl = TextEditingController();
  final _shopCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  final FocusNode _pinFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _checkRegistration();
  }

  void _checkRegistration() async {
    bool registered = await DatabaseHelper.instance.isUserRegistered();
    setState(() { _isRegistered = registered; _isLoading = false; });
    if (registered) Future.delayed(const Duration(milliseconds: 500), () { if (mounted) FocusScope.of(context).requestFocus(_pinFocusNode); });
  }

  void _handleLogin(String pin) async {
    if (pin.length != 4) return;
    final user = await DatabaseHelper.instance.getUser();
    if (user != null && user['pin'] == pin) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Incorrect PIN"), backgroundColor: Colors.red));
      _pinCtrl.clear();
      setState(() {});
    }
  }

  void _handleRegister() async {
    if (_nameCtrl.text.isEmpty || _pinCtrl.text.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Valid Name and 4-digit PIN required"), backgroundColor: Colors.red)); return;
    }
    await DatabaseHelper.instance.registerUser(_nameCtrl.text, _shopCtrl.text, _pinCtrl.text, _phoneCtrl.text, _addressCtrl.text);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle), child: Icon(Icons.storefront_rounded, size: 60, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 24),
                Text(_isRegistered ? "Welcome Back" : "Setup Business", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                const SizedBox(height: 8),
                Text(_isRegistered ? "Enter PIN to unlock dashboard" : "Create profile & set a secure PIN", style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                const SizedBox(height: 48),

                if (!_isRegistered) ...[
                  TextField(controller: _nameCtrl, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: "Your Name", prefixIcon: Icon(Icons.person))),
                  const SizedBox(height: 16),
                  TextField(controller: _shopCtrl, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: "Shop/Business Name", prefixIcon: Icon(Icons.store))),
                  const SizedBox(height: 16),
                  TextField(controller: _phoneCtrl, textInputAction: TextInputAction.next, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Phone Number", prefixIcon: Icon(Icons.phone))),
                  const SizedBox(height: 16),
                  TextField(controller: _addressCtrl, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: "Shop Address", prefixIcon: Icon(Icons.location_on))),
                  const SizedBox(height: 32),
                ],

                Text("Enter 4-Digit PIN", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700, fontSize: 16)),
                const SizedBox(height: 16),

                SizedBox(
                  height: 60, width: 300,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0,
                          child: TextField(
                            controller: _pinCtrl, focusNode: _pinFocusNode, keyboardType: TextInputType.number, maxLength: 4, showCursor: false, enableInteractiveSelection: false,
                            decoration: const InputDecoration(border: InputBorder.none, counterText: ""),
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onChanged: (val) { setState(() {}); if (val.length == 4 && _isRegistered) _handleLogin(val); },
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(4, (index) {
                              bool isFilled = index < _pinCtrl.text.length;
                              return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 10), width: 55, height: 55,
                                  decoration: BoxDecoration(border: Border.all(color: isFilled ? Colors.indigo : Colors.grey.shade300, width: 2), borderRadius: BorderRadius.circular(16), color: isFilled ? Colors.indigo.shade50 : Colors.white),
                                  child: Center(child: isFilled ? const Icon(Icons.circle, size: 16, color: Colors.indigo) : null)
                              );
                            })
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),
                if (!_isRegistered)
                  SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _handleRegister, child: const Text("LAUNCH DASHBOARD")))
              ],
            ),
          ),
        ),
      ),
    );
  }
}