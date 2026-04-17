import 'package:flutter/material.dart';
import '../database_helper.dart';

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key});
  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> filteredCustomers = [];
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
    _searchCtrl.addListener(_filter);
  }

  void _refresh() async {
    final d = await DatabaseHelper.instance.getCustomers();
    setState(() {
      customers = d;
      filteredCustomers = d;
    });
    _filter();
  }

  void _filter() {
    String query = _searchCtrl.text.toLowerCase();
    setState(() {
      filteredCustomers = customers.where((c) {
        return c['name'].toLowerCase().contains(query) ||
            c['phone'].contains(query);
      }).toList();
    });
  }

  // Handle Add & Edit
  void _showCustomerForm({Map<String, dynamic>? customer}) {
    final nameCtrl = TextEditingController(text: customer?['name']);
    final phoneCtrl = TextEditingController(text: customer?['phone']);
    final addrCtrl = TextEditingController(text: customer?['address']);
    bool isEditing = customer != null;

    showDialog(context: context, builder: (_) => AlertDialog(
        title: Text(isEditing ? "Edit Customer" : "Add Customer"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Name", prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: "Phone", prefixIcon: Icon(Icons.phone)),
              keyboardType: TextInputType.phone,
              readOnly: isEditing, // Phone is ID, usually shouldn't change
              style: TextStyle(color: isEditing ? Colors.grey : Colors.black),
            ),
            const SizedBox(height: 10),
            TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: "Address", prefixIcon: Icon(Icons.location_on))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name and Phone are required")));
                  return;
                }
                try {
                  final data = {'name': nameCtrl.text, 'phone': phoneCtrl.text, 'address': addrCtrl.text};
                  if (isEditing) {
                    await DatabaseHelper.instance.updateCustomer(data);
                  } else {
                    await DatabaseHelper.instance.addCustomer(data);
                  }
                  if(mounted) Navigator.pop(context);
                  _refresh();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Phone number may already exist!")));
                }
              },
              child: const Text("SAVE")
          )
        ]
    ));
  }

  void _deleteCustomer(String phone) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text("Delete Customer?"),
      content: const Text("This will delete the customer profile."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
        TextButton(onPressed: () async {
          await DatabaseHelper.instance.deleteCustomer(phone);
          if(mounted) Navigator.pop(context);
          _refresh();
        }, child: const Text("DELETE", style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  void _showDetails(Map<String, dynamic> c) async {
    final inv = await DatabaseHelper.instance.getCustomerInvoices(c['phone']);
    if(!mounted) return;

    showDialog(context: context, builder: (_) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [const Icon(Icons.phone, size: 16, color: Colors.grey), const SizedBox(width: 8), Text(c['phone'])]),
                const SizedBox(height: 5),
                Row(children: [const Icon(Icons.location_on, size: 16, color: Colors.grey), const SizedBox(width: 8), Expanded(child: Text(c['address'] ?? 'No Address'))]),

                const SizedBox(height: 15),
                const Text("Invoice History:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                const SizedBox(height: 5),

                if (inv.isEmpty)
                  const Padding(padding: EdgeInsets.all(10), child: Text("No invoices found.", style: TextStyle(color: Colors.grey)))
                else
                  ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: inv.length,
                      separatorBuilder: (_,__) => const Divider(height: 1),
                      itemBuilder: (context, x) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text("Inv #${inv[x]['id']} - ${inv[x]['date'].toString().substring(0, 10)}"),
                        trailing: Text("₹ ${inv[x]['total_amount']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      )
                  ),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: const Text("CLOSE"))]
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text("Customers")),
        floatingActionButton: FloatingActionButton(onPressed: () => _showCustomerForm(), child: const Icon(Icons.add)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(labelText: "Search Name or Phone", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
              ),
            ),
            Expanded(
              child: ListView.separated(
                  separatorBuilder: (_,__) => const Divider(height: 1),
                  itemCount: filteredCustomers.length,
                  itemBuilder: (ctx, i) {
                    final c = filteredCustomers[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.indigo.shade50,
                        child: Text(c['name'].isNotEmpty ? c['name'][0].toUpperCase() : "?", style: const TextStyle(color: Colors.indigo)),
                      ),
                      title: Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(c['phone']),
                      onTap: () => _showDetails(c),
                      // UPDATED: Buttons like Expense Screen
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                              onPressed: () => _showCustomerForm(customer: c)
                          ),
                          IconButton(
                              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                              onPressed: () => _deleteCustomer(c['phone'])
                          ),
                        ],
                      ),
                    );
                  }
              ),
            ),
          ],
        )
    );
  }
}