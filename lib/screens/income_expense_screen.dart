import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';

class IncomeExpenseScreen extends StatelessWidget {
  const IncomeExpenseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Cashbook", style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
              labelColor: Colors.indigo, unselectedLabelColor: Colors.grey, indicatorColor: Colors.indigo, indicatorWeight: 3,
              tabs: [Tab(text: "Expenses (Out)"), Tab(text: "Income (In)")]
          ),
        ),
        body: const TabBarView(children: [
          _CashList(isExpense: true),
          _CashList(isExpense: false),
        ]),
      ),
    );
  }
}

class _CashList extends StatefulWidget {
  final bool isExpense;
  const _CashList({required this.isExpense});
  @override
  State<_CashList> createState() => _CashListState();
}

class _CashListState extends State<_CashList> {
  List<Map<String, dynamic>> items = [];

  @override
  void initState() { super.initState(); _refresh(); }

  void _refresh() async {
    final data = widget.isExpense ? await DatabaseHelper.instance.getExpenses() : await DatabaseHelper.instance.getIncomes();
    if (mounted) setState(() => items = data);
  }

  void _showForm({Map<String, dynamic>? item}) {
    final titleCtrl = TextEditingController(text: item?['title']);
    final amtCtrl = TextEditingController(text: item?['amount']?.toString());
    bool isEdit = item != null;

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
                Text(isEdit ? "Edit Entry" : (widget.isExpense ? "Add Expense" : "Add Income"), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Description (e.g. Rent, Bill)")),
                const SizedBox(height: 12),
                TextField(controller: amtCtrl, decoration: const InputDecoration(labelText: "Amount"), keyboardType: TextInputType.number),
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
                  if (titleCtrl.text.isEmpty || amtCtrl.text.isEmpty) return;
                  final data = {'title': titleCtrl.text, 'amount': double.parse(amtCtrl.text), 'date': item?['date'] ?? DateTime.now().toIso8601String()};
                  if (isEdit) {
                    data['id'] = item['id'];
                    widget.isExpense ? await DatabaseHelper.instance.updateExpense(data) : await DatabaseHelper.instance.updateIncome(data);
                  } else {
                    widget.isExpense ? await DatabaseHelper.instance.addExpense(data) : await DatabaseHelper.instance.addIncome(data);
                  }
                  if(mounted) Navigator.pop(context);
                  _refresh();
                }, child: const Text("SAVE")))
              ]),
            ),
          ),
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    Color themeColor = widget.isExpense ? Colors.red : Colors.green;
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _showForm, backgroundColor: themeColor, child: const Icon(Icons.add, color: Colors.white)),
      body: items.isEmpty
          ? Center(child: Text("No records found", style: TextStyle(color: Colors.grey.shade600)))
          : ListView.separated(
        padding: const EdgeInsets.all(16), itemCount: items.length, separatorBuilder: (_,__) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final item = items[i];
          DateTime date = DateTime.parse(item['date']);
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(backgroundColor: themeColor.withOpacity(0.1), child: Icon(widget.isExpense ? Icons.arrow_outward : Icons.arrow_downward, color: themeColor)),
              title: Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text(DateFormat('MMM dd, yyyy').format(date)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text("₹${item['amount']}", style: TextStyle(fontWeight: FontWeight.bold, color: themeColor, fontSize: 16)),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: () => _showForm(item: item)),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () async {
                  widget.isExpense ? await DatabaseHelper.instance.deleteExpense(item['id']) : await DatabaseHelper.instance.deleteIncome(item['id']);
                  _refresh();
                }),
              ]),
            ),
          );
        },
      ),
    );
  }
}