import 'package:flutter/material.dart';
import '../database_helper.dart';

class FinanceListScreen extends StatefulWidget {
  final String type;
  const FinanceListScreen({super.key, required this.type});

  @override
  State<FinanceListScreen> createState() => _FinanceListScreenState();
}

class _FinanceListScreenState extends State<FinanceListScreen> {
  @override
  Widget build(BuildContext context) {
    if (widget.type == 'receivable') {
      return DefaultTabController(
          length: 2,
          child: Scaffold(
              appBar: AppBar(
                  title: const Text("Credit & Receivables", style: TextStyle(fontWeight: FontWeight.bold)),
                  bottom: const TabBar(
                      labelColor: Colors.indigo, unselectedLabelColor: Colors.grey, indicatorColor: Colors.indigo, indicatorWeight: 3,
                      tabs: [Tab(text: "Unpaid Bills"), Tab(text: "Other Lent Money")]
                  )
              ),
              body: const TabBarView(children: [FinanceTab(category: 'sales'), FinanceTab(category: 'other')])
          )
      );
    } else {
      return Scaffold(appBar: AppBar(title: const Text("Payables & Debt", style: TextStyle(fontWeight: FontWeight.bold))), body: const FinanceTab(category: 'payable'));
    }
  }
}

class FinanceTab extends StatefulWidget {
  final String category;
  const FinanceTab({super.key, required this.category});
  @override
  State<FinanceTab> createState() => _FinanceTabState();
}

class _FinanceTabState extends State<FinanceTab> {
  List<Map<String, dynamic>> items = [];
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _refresh(); _searchCtrl.addListener(_refresh); }

  void _refresh() async {
    final db = await DatabaseHelper.instance.database;
    String q = _searchCtrl.text;
    List<Map<String, dynamic>> data = [];
    if (widget.category == 'sales') {
      String sql = "SELECT * FROM invoices WHERE 1=1";
      if (q.isNotEmpty) sql += " AND (customer_name LIKE '%$q%' OR id LIKE '%$q%')";
      sql += " ORDER BY balance_due DESC, date DESC";
      data = await db.rawQuery(sql);
    } else if (widget.category == 'other') {
      String sql = "SELECT * FROM other_receivables WHERE 1=1";
      if (q.isNotEmpty) sql += " AND title LIKE '%$q%'";
      sql += " ORDER BY balance_due DESC, date DESC";
      data = await db.rawQuery(sql);
    } else {
      String sql = "SELECT * FROM payables WHERE 1=1";
      if (q.isNotEmpty) sql += " AND title LIKE '%$q%'";
      sql += " ORDER BY balance_due DESC, date DESC";
      data = await db.rawQuery(sql);
    }
    if (mounted) setState(() => items = data);
  }

  void _showAddDialog() {
    final tCtrl = TextEditingController(), aCtrl = TextEditingController();
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        // FIXED: Using sheetContext to perfectly track keyboard height
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Add ${widget.category == 'payable' ? 'Payable (Debt)' : 'Receivable (Lent)'}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextField(controller: tCtrl, decoration: const InputDecoration(labelText: "Description (e.g. Supplier Name)")),
                const SizedBox(height: 12),
                TextField(controller: aCtrl, decoration: const InputDecoration(labelText: "Total Amount"), keyboardType: TextInputType.number),
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
                  if(tCtrl.text.isNotEmpty && aCtrl.text.isNotEmpty) {
                    double amt = double.tryParse(aCtrl.text) ?? 0;
                    final row = {'title': tCtrl.text, 'amount': amt, 'balance_due': amt, 'date': DateTime.now().toString()};
                    widget.category == 'other' ? await DatabaseHelper.instance.addOtherReceivable(row) : await DatabaseHelper.instance.addPayable(row);
                    if(mounted) Navigator.pop(context);
                    _refresh();
                  }
                }, child: const Text("SAVE")))
              ]),
            ),
          ),
        )
    );
  }

  void _showSettleDialog(Map<String, dynamic> item) {
    final amtCtrl = TextEditingController(); double due = item['balance_due'];
    showDialog(context: context, builder: (_) => AlertDialog(
        title: const Text("Settle Amount"),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text("Balance Due: ₹ $due", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            TextField(controller: amtCtrl, decoration: const InputDecoration(labelText: "Enter Amount Paid"), keyboardType: TextInputType.number)
          ]),
        ),
        actions: [TextButton(onPressed: () async {
          double paid = double.tryParse(amtCtrl.text) ?? 0;
          if (paid > 0 && paid <= due) {
            if (widget.category == 'sales') await DatabaseHelper.instance.settleInvoice(item['id'], paid);
            else if (widget.category == 'other') await DatabaseHelper.instance.settleOtherReceivable(item['id'], paid);
            else await DatabaseHelper.instance.settlePayable(item['id'], paid);
            if(mounted) Navigator.pop(context);
            _refresh();
          }
        }, child: const Text("PAY NOW", style: TextStyle(fontWeight: FontWeight.bold)))]
    ));
  }

  void _showHistory(Map<String, dynamic> item) async {
    String typeStr = widget.category == 'sales' ? 'receivable' : (widget.category == 'other' ? 'other_receivable' : 'payable');
    final history = await DatabaseHelper.instance.getSettlementHistory(item['id'], typeStr);
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (_) => Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Payment History", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 16),
      history.isEmpty ? const Text("No payments yet.") : ListView.separated(shrinkWrap: true, itemCount: history.length, separatorBuilder: (_,__) => const Divider(), itemBuilder: (ctx, i) => ListTile(contentPadding: EdgeInsets.zero, title: Text("Paid: ₹${history[i]['amount']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)), subtitle: Text(history[i]['date'].toString().substring(0,10))))
    ])));
  }

  @override
  Widget build(BuildContext context) {
    Color themeColor = widget.category == 'payable' ? Colors.red : Colors.orange;
    return Scaffold(
      floatingActionButton: widget.category != 'sales' ? FloatingActionButton(onPressed: _showAddDialog, backgroundColor: themeColor, child: const Icon(Icons.add, color: Colors.white)) : null,
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _searchCtrl, decoration: const InputDecoration(labelText: "Search records...", prefixIcon: Icon(Icons.search)))),
          Expanded(
            child: items.isEmpty ? Center(child: Text("No records found", style: TextStyle(color: Colors.grey[600]))) : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16), separatorBuilder: (_,__) => const SizedBox(height: 10), itemCount: items.length,
              itemBuilder: (ctx, i) {
                final item = items[i];
                String title = widget.category == 'sales' ? "${item['customer_name']} (Inv#${item['id']})" : item['title'];
                double due = item['balance_due']; bool isSettled = due <= 0;
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(backgroundColor: isSettled ? Colors.green.withOpacity(0.1) : themeColor.withOpacity(0.1), child: Icon(isSettled ? Icons.check : (widget.category == 'payable' ? Icons.upload : Icons.download), color: isSettled ? Colors.green : themeColor)),
                    title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, decoration: isSettled ? TextDecoration.lineThrough : null, color: isSettled ? Colors.grey : Colors.black, fontSize: 16)),
                    subtitle: isSettled ? const Text("SETTLED", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)) : Text("Due: ₹ $due", style: TextStyle(color: themeColor, fontSize: 13, fontWeight: FontWeight.bold)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isSettled) ElevatedButton(onPressed: () => _showSettleDialog(item), style: ElevatedButton.styleFrom(backgroundColor: themeColor.withOpacity(0.1), foregroundColor: themeColor, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 12)), child: const Text("PAY")),
                        IconButton(icon: const Icon(Icons.history, color: Colors.blue), onPressed: () => _showHistory(item)),
                        if (widget.category != 'sales') IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () async { await DatabaseHelper.instance.deletePayable(item['id']); _refresh(); }),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}