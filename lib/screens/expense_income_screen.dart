import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';

class ExpenseIncomeScreen extends StatefulWidget {
  final String type; // 'expense' or 'income'
  const ExpenseIncomeScreen({super.key, required this.type});

  @override
  State<ExpenseIncomeScreen> createState() => _ExpenseIncomeScreenState();
}

class _ExpenseIncomeScreenState extends State<ExpenseIncomeScreen> {
  List<Map<String, dynamic>> items = [];
  bool get isExpense => widget.type == 'expense';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final data = isExpense
        ? await DatabaseHelper.instance.getExpenses()
        : await DatabaseHelper.instance.getIncomes();
    setState(() => items = data);
  }

  void _showAddDialog({Map<String, dynamic>? item}) {
    final titleCtrl = TextEditingController(text: item?['title']);
    final amtCtrl = TextEditingController(text: item?['amount']?.toString());

    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text(item == null ? "Add ${isExpense ? 'Expense' : 'Income'}" : "Edit Item"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Description (e.g. Rent)")),
        const SizedBox(height: 10),
        TextField(controller: amtCtrl, decoration: const InputDecoration(labelText: "Amount"), keyboardType: TextInputType.number),
      ]),
      actions: [
        TextButton(onPressed: () async {
          if (titleCtrl.text.isNotEmpty && amtCtrl.text.isNotEmpty) {
            final row = {
              'title': titleCtrl.text,
              'amount': double.tryParse(amtCtrl.text) ?? 0.0,
              'date': item?['date'] ?? DateTime.now().toString(),
            };

            if (item == null) {
              if (isExpense) await DatabaseHelper.instance.addExpense(row);
              else await DatabaseHelper.instance.addIncome(row);
            } else {
              row['id'] = item['id'];
              if (isExpense) await DatabaseHelper.instance.updateExpense(row);
              else await DatabaseHelper.instance.updateIncome(row);
            }

            if(mounted) Navigator.pop(context);
            _loadData();
          }
        }, child: const Text("SAVE"))
      ],
    ));
  }

  void _delete(int id) async {
    if (isExpense) await DatabaseHelper.instance.deleteExpense(id);
    else await DatabaseHelper.instance.deleteIncome(id);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isExpense ? "Manage Expenses" : "Other Income")),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(),
        backgroundColor: isExpense ? Colors.red : Colors.green,
        child: const Icon(Icons.add),
      ),
      body: items.isEmpty
          ? Center(child: Text("No ${isExpense ? 'expenses' : 'income'} recorded", style: const TextStyle(color: Colors.grey)))
          : ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1), // Clean divider
        itemBuilder: (ctx, i) {
          final item = items[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            leading: CircleAvatar(
              backgroundColor: isExpense ? Colors.red.shade50 : Colors.green.shade50,
              child: Icon(
                isExpense ? Icons.money_off : Icons.attach_money,
                color: isExpense ? Colors.red : Colors.green,
                size: 20,
              ),
            ),
            title: Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(DateFormat('dd MMM yyyy').format(DateTime.parse(item['date']))),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    "₹${item['amount']}",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isExpense ? Colors.red : Colors.green
                    )
                ),
                const SizedBox(width: 10),
                IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.blue), onPressed: () => _showAddDialog(item: item)),
                IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.grey), onPressed: () => _delete(item['id'])),
              ],
            ),
          );
        },
      ),
    );
  }
}