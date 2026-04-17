import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';
import '../pdf_generator.dart'; // Import for printing

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});
  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  List<Map<String, dynamic>> invoices = [];
  List<Map<String, dynamic>> filteredInvoices = [];
  TextEditingController searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    searchCtrl.addListener(_filter);
  }

  void _loadData() async {
    final data = await DatabaseHelper.instance.getAllInvoices();
    setState(() {
      invoices = data;
      filteredInvoices = data;
    });
  }

  void _filter() {
    String query = searchCtrl.text.toLowerCase();
    setState(() {
      filteredInvoices = invoices.where((i) {
        return i['customer_name'].toLowerCase().contains(query) ||
            i['id'].toString().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sales History")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: searchCtrl,
              decoration: const InputDecoration(
                  labelText: "Search by Name or Invoice #",
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder()
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: filteredInvoices.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (ctx, i) {
                final inv = filteredInvoices[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.shade50,
                    child: Text("#${inv['id']}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  ),
                  title: Text(inv['customer_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(inv['date']))),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("₹ ${inv['total_amount'].toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(inv['balance_due'] > 0 ? "Due: ${inv['balance_due']}" : "Paid", style: TextStyle(fontSize: 11, color: inv['balance_due'] > 0 ? Colors.red : Colors.green)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.print, color: Colors.blueGrey),
                        onPressed: () => PdfGenerator.generateAndPrint(inv['id']),
                        tooltip: "View/Print Bill",
                      )
                    ],
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}