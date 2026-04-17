import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';
import '../pdf_generator.dart';
import 'login_screen.dart';
import 'invoice_screen.dart';
import 'inventory_screen.dart';
import 'contact_screen.dart';
import 'report_screen.dart';
import 'finance_list_screen.dart';
import 'sales_history_screen.dart';
import 'income_expense_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  String _shopName = "My Shop";
  String _userName = "User";

  // UPDATED: Changed keys to reflect current month
  Map<String, double> _stats = {
    'current_month_sales': 0,
    'current_month_net_profit': 0,
    'receivables': 0,
    'payables': 0
  };

  List<Map<String, dynamic>> _recentInvoices = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  void _loadDashboardData() async {
    final user = await DatabaseHelper.instance.getUser();
    final stats = await DatabaseHelper.instance.getStats();
    final allInvoices = await DatabaseHelper.instance.getAllInvoices();

    if (mounted) {
      setState(() {
        if (user != null) {
          _shopName = user['shop_name'] ?? "My Shop";
          _userName = user['name'] ?? "User";
        }
        _stats = stats;
        _recentInvoices = allInvoices.take(5).toList();
        _isLoading = false;
      });
    }
  }

  String fmt(double val) => "₹${val.toStringAsFixed(0)}";

  void _showSettingsModal() async {
    final user = await DatabaseHelper.instance.getUser();
    final nameCtrl = TextEditingController(text: user?['name'] ?? '');
    final shopCtrl = TextEditingController(text: user?['shop_name'] ?? '');
    final phoneCtrl = TextEditingController(text: user?['phone'] ?? '');
    final addressCtrl = TextEditingController(text: user?['address'] ?? '');

    if (!mounted) return;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Business Profile", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Your Name", prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 12),
            TextField(controller: shopCtrl, decoration: const InputDecoration(labelText: "Shop Name", prefixIcon: Icon(Icons.store))),
            const SizedBox(height: 12),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "Phone", prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: "Address", prefixIcon: Icon(Icons.location_on))),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty) return;
                  await DatabaseHelper.instance.updateUserProfile(nameCtrl.text, shopCtrl.text, phoneCtrl.text, addressCtrl.text);
                  if (mounted) Navigator.pop(context);
                  _loadDashboardData();
                },
                child: const Text("SAVE CHANGES"),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _logout() {
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Welcome, $_userName", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(_shopName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _showSettingsModal),
          IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent), onPressed: _logout),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoiceScreen())).then((_) => _loadDashboardData()),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text("NEW BILL", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
      ),

      body: RefreshIndicator(
        onRefresh: () async => _loadDashboardData(),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          children: [
            const Text("Business Overview", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            const SizedBox(height: 12),
            Row(children: [
              // UPDATED: Now points to current_month_net_profit and current_month_sales
              _buildStatCard("This Month Profit", fmt(_stats['current_month_net_profit']!), Icons.trending_up_rounded, Colors.green),
              const SizedBox(width: 12),
              _buildStatCard("This Month Sales", fmt(_stats['current_month_sales']!), Icons.point_of_sale_rounded, Colors.blue),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _buildStatCard("To Collect", fmt(_stats['receivables']!), Icons.arrow_downward_rounded, Colors.orange,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinanceListScreen(type: 'receivable'))).then((_) => _loadDashboardData())),
              const SizedBox(width: 12),
              _buildStatCard("To Pay", fmt(_stats['payables']!), Icons.arrow_upward_rounded, Colors.red,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinanceListScreen(type: 'payable'))).then((_) => _loadDashboardData())),
            ]),

            const SizedBox(height: 30),
            const Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              runSpacing: 16,
              children: [
                _buildActionBtn("Inventory", Icons.inventory_2_rounded, Colors.purple, const InventoryScreen()),
                _buildActionBtn("Contacts", Icons.people_alt_rounded, Colors.teal, const ContactScreen()),
                _buildActionBtn("Cashbook", Icons.receipt_long_rounded, Colors.pink, const IncomeExpenseScreen()),
                _buildActionBtn("Reports", Icons.bar_chart_rounded, Theme.of(context).colorScheme.primary, const ReportScreen()),
              ],
            ),

            const SizedBox(height: 35),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Recent Invoices", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesHistoryScreen())).then((_) => _loadDashboardData()),
                  child: Text("View All", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                )
              ],
            ),
            const SizedBox(height: 8),

            if (_recentInvoices.isEmpty)
              Card(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text("No sales yet. Tap 'NEW BILL' to start!", style: TextStyle(color: Colors.grey.shade600)))))
            else
              Card(
                child: ListView.separated(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _recentInvoices.length, separatorBuilder: (_,__) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final inv = _recentInvoices[i];
                    bool isPaid = inv['balance_due'] <= 0;
                    DateTime date = DateTime.parse(inv['date']);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          child: Text("#${inv['id']}", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary, fontSize: 13))
                      ),
                      title: Text(inv['customer_name'] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(DateFormat('MMM dd, hh:mm a').format(date), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(fmt(inv['total_amount']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: isPaid ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(4)), child: Text(isPaid ? "PAID" : "DUE", style: TextStyle(color: isPaid ? Colors.green : Colors.red, fontSize: 10, fontWeight: FontWeight.bold)))
                        ],
                      ),
                      onTap: () async => await PdfGenerator.generateAndPrint(inv['id']),
                    );
                  },
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String amount, IconData icon, Color color, {VoidCallback? onTap}) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero, shadowColor: color.withOpacity(0.2), elevation: 4,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 18)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 16),
                Text(amount, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionBtn(String title, IconData icon, Color color, Widget targetScreen) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => targetScreen)).then((_) => _loadDashboardData()),
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 75,
        child: Column(
          children: [
            Container(height: 55, width: 55, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 26)),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800), textAlign: TextAlign.center, maxLines: 1),
          ],
        ),
      ),
    );
  }
}