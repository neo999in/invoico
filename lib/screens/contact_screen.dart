import 'package:flutter/material.dart';
import '../database_helper.dart';

class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Contacts Book", style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            labelColor: Colors.indigo,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.indigo,
            indicatorWeight: 3,
            tabs: [
              Tab(icon: Icon(Icons.people), text: "Customers"),
              Tab(icon: Icon(Icons.local_shipping), text: "Suppliers"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            CustomerTab(),
            SupplierTab(),
          ],
        ),
      ),
    );
  }
}

// ==========================================
//               CUSTOMER TAB
// ==========================================

class CustomerTab extends StatefulWidget {
  const CustomerTab({super.key});
  @override
  State<CustomerTab> createState() => _CustomerTabState();
}

class _CustomerTabState extends State<CustomerTab> {
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> filteredCustomers = [];
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
    _searchCtrl.addListener(_filter);
  }

  // FIXED: Added dispose method to prevent memory leaks
  @override
  void dispose() {
    _searchCtrl.removeListener(_filter);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() async {
    final d = await DatabaseHelper.instance.getCustomers();
    if (mounted) setState(() { customers = d; filteredCustomers = d; });
    _filter();
  }

  void _filter() {
    String query = _searchCtrl.text.toLowerCase();
    if (mounted) {
      setState(() {
        filteredCustomers = customers.where((c) => c['name'].toLowerCase().contains(query) || c['phone'].contains(query)).toList();
      });
    }
  }

  void _showCustomerForm({Map<String, dynamic>? customer}) {
    final nameCtrl = TextEditingController(text: customer?['name']);
    final phoneCtrl = TextEditingController(text: customer?['phone']);
    final addrCtrl = TextEditingController(text: customer?['address']);
    bool isEditing = customer != null;

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        // FIXED: Renamed builder context to sheetContext
        builder: (sheetContext) => SingleChildScrollView(
          child: Padding(
            // FIXED: Used sheetContext here so it reads the bottom sheet's padding!
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetContext).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isEditing ? "Edit Customer" : "Add New Customer", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Full Name", prefixIcon: Icon(Icons.person))),
                const SizedBox(height: 12),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "Phone Number", prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone, readOnly: isEditing, style: TextStyle(color: isEditing ? Colors.grey : Colors.black)),
                const SizedBox(height: 12),
                TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: "Address", prefixIcon: Icon(Icons.location_on))),
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
                  if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty) return;
                  try {
                    final data = {'name': nameCtrl.text, 'phone': phoneCtrl.text, 'address': addrCtrl.text};
                    isEditing ? await DatabaseHelper.instance.updateCustomer(data) : await DatabaseHelper.instance.addCustomer(data);
                    if (mounted) Navigator.pop(context); _refresh();
                  } catch (e) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Phone already exists!"))); }
                }, child: const Text("SAVE CUSTOMER")))
              ],
            ),
          ),
        )
    );
  }

  void _deleteCustomer(String phone) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text("Delete Customer?"),
      content: const Text("This removes the customer profile. Invoices will remain but unlinked."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
        TextButton(onPressed: () async { await DatabaseHelper.instance.deleteCustomer(phone); if (mounted) Navigator.pop(context); _refresh(); }, child: const Text("DELETE", style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  void _showDetails(Map<String, dynamic> c) async {
    final inv = await DatabaseHelper.instance.getCustomerInvoices(c['phone']);
    if (!mounted) return;

    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.9, expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 24, backgroundColor: Colors.indigo.shade50, child: Text(c['name'][0].toUpperCase(), style: const TextStyle(fontSize: 24, color: Colors.indigo, fontWeight: FontWeight.bold))),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c['name'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(children: [const Icon(Icons.phone, size: 14, color: Colors.grey), const SizedBox(width: 4), Text(c['phone'], style: TextStyle(color: Colors.grey.shade700))]),
                const SizedBox(height: 4),
                Row(children: [const Icon(Icons.location_on, size: 14, color: Colors.grey), const SizedBox(width: 4), Expanded(child: Text(c['address'] ?? 'No Address', style: TextStyle(color: Colors.grey.shade700), maxLines: 1, overflow: TextOverflow.ellipsis))]),
              ])),
            ]),
            const SizedBox(height: 24),
            const Text("Purchase History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo)),
            const SizedBox(height: 12),
            Expanded(child: inv.isEmpty ? const Center(child: Text("No purchases yet", style: TextStyle(color: Colors.grey))) : ListView.separated(
                controller: scrollCtrl, itemCount: inv.length, separatorBuilder: (_,__) => const SizedBox(height: 8),
                itemBuilder: (context, x) => Card(
                  color: Colors.grey.shade50, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                  child: ListTile(
                    title: Text("Inv #${inv[x]['id']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(inv[x]['date'].toString().substring(0, 10)),
                    trailing: Text("₹${inv[x]['total_amount']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                  ),
                )
            ))
          ]),
        )
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showCustomerForm(),
            icon: const Icon(Icons.person_add),
            label: const Text("Customer")
        ),
        body: Column(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _searchCtrl, decoration: const InputDecoration(labelText: "Search Name or Phone", prefixIcon: Icon(Icons.search)))),
            Expanded(
              child: ListView.separated(
                // FIXED: Dismiss keyboard when user scrolls the list
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  separatorBuilder: (_,__) => const SizedBox(height: 10), itemCount: filteredCustomers.length,
                  itemBuilder: (ctx, i) {
                    final c = filteredCustomers[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(backgroundColor: Colors.indigo.shade50, child: Text(c['name'][0].toUpperCase(), style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold))),
                        title: Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Text(c['phone'], style: TextStyle(color: Colors.grey.shade600)),
                        onTap: () => _showDetails(c),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.blue), onPressed: () => _showCustomerForm(customer: c)),
                            IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), onPressed: () => _deleteCustomer(c['phone'])),
                          ],
                        ),
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

// ==========================================
//               SUPPLIER TAB
// ==========================================

class SupplierTab extends StatefulWidget {
  const SupplierTab({super.key});
  @override
  State<SupplierTab> createState() => _SupplierTabState();
}

class _SupplierTabState extends State<SupplierTab> {
  List<Map<String, dynamic>> suppliers = [];
  List<Map<String, dynamic>> filteredSuppliers = [];
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
    _searchCtrl.addListener(_filter);
  }

  // FIXED: Added dispose method to prevent memory leaks
  @override
  void dispose() {
    _searchCtrl.removeListener(_filter);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() async {
    final d = await DatabaseHelper.instance.getSuppliers();
    if (mounted) setState(() { suppliers = d; filteredSuppliers = d; });
    _filter();
  }

  void _filter() {
    String query = _searchCtrl.text.toLowerCase();
    if (mounted) {
      setState(() {
        filteredSuppliers = suppliers.where((s) => s['name'].toLowerCase().contains(query) || (s['phone']?.contains(query) ?? false)).toList();
      });
    }
  }

  void _showSupplierForm({Map<String, dynamic>? supplier}) {
    final nameCtrl = TextEditingController(text: supplier?['name']);
    final phoneCtrl = TextEditingController(text: supplier?['phone']);
    final addrCtrl = TextEditingController(text: supplier?['address']);
    bool isEditing = supplier != null;

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        // FIXED: Renamed builder context to sheetContext
        builder: (sheetContext) => SingleChildScrollView(
          child: Padding(
            // FIXED: Used sheetContext here!
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetContext).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isEditing ? "Edit Supplier" : "Add New Supplier", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Business/Supplier Name", prefixIcon: Icon(Icons.store))),
                const SizedBox(height: 12),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "Phone Number", prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: "Address", prefixIcon: Icon(Icons.location_on))),
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    onPressed: () async {
                      if (nameCtrl.text.isEmpty) return;
                      try {
                        final data = {'name': nameCtrl.text, 'phone': phoneCtrl.text, 'address': addrCtrl.text};
                        if (isEditing) data['id'] = supplier['id'];
                        isEditing ? await DatabaseHelper.instance.updateSupplier(data) : await DatabaseHelper.instance.addSupplier(data);
                        if (mounted) Navigator.pop(context); _refresh();
                      } catch (e) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error saving supplier!"))); }
                    }, child: const Text("SAVE SUPPLIER")))
              ],
            ),
          ),
        )
    );
  }

  void _deleteSupplier(int id) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text("Delete Supplier?"),
      content: const Text("This removes the supplier profile. Historical stock purchases will remain intact."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
        TextButton(onPressed: () async { await DatabaseHelper.instance.deleteSupplier(id); if (mounted) Navigator.pop(context); _refresh(); }, child: const Text("DELETE", style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  void _showDetails(Map<String, dynamic> s) async {
    final purchases = await DatabaseHelper.instance.getSupplierPurchases(s['name']);
    if (!mounted) return;

    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.9, expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 24, backgroundColor: Colors.teal.shade50, child: const Icon(Icons.local_shipping, size: 24, color: Colors.teal)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s['name'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(children: [const Icon(Icons.phone, size: 14, color: Colors.grey), const SizedBox(width: 4), Text(s['phone'] ?? 'N/A', style: TextStyle(color: Colors.grey.shade700))]),
                const SizedBox(height: 4),
                Row(children: [const Icon(Icons.location_on, size: 14, color: Colors.grey), const SizedBox(width: 4), Expanded(child: Text(s['address'] ?? 'No Address', style: TextStyle(color: Colors.grey.shade700), maxLines: 1, overflow: TextOverflow.ellipsis))]),
              ])),
            ]),
            const SizedBox(height: 24),
            const Text("Stock Supplied", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal)),
            const SizedBox(height: 12),
            Expanded(child: purchases.isEmpty ? const Center(child: Text("No purchases logged from this supplier", style: TextStyle(color: Colors.grey))) : ListView.separated(
                controller: scrollCtrl, itemCount: purchases.length, separatorBuilder: (_,__) => const SizedBox(height: 8),
                itemBuilder: (context, x) => Card(
                  color: Colors.grey.shade50, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2, color: Colors.grey),
                    title: Text(purchases[x]['product_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(purchases[x]['date'].toString().substring(0, 10)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("₹${purchases[x]['cost']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 14)),
                        Text("${purchases[x]['quantity']} units", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                  ),
                )
            ))
          ]),
        )
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        floatingActionButton: FloatingActionButton.extended(
            backgroundColor: Colors.teal,
            onPressed: () => _showSupplierForm(),
            icon: const Icon(Icons.add_business, color: Colors.white),
            label: const Text("Supplier", style: TextStyle(color: Colors.white))
        ),
        body: Column(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _searchCtrl, decoration: const InputDecoration(labelText: "Search Supplier", prefixIcon: Icon(Icons.search)))),
            Expanded(
              child: ListView.separated(
                // FIXED: Dismiss keyboard when user scrolls the list
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  separatorBuilder: (_,__) => const SizedBox(height: 10), itemCount: filteredSuppliers.length,
                  itemBuilder: (ctx, i) {
                    final s = filteredSuppliers[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(backgroundColor: Colors.teal.shade50, child: Text(s['name'][0].toUpperCase(), style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold))),
                        title: Text(s['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Text(s['phone'] ?? 'No Phone', style: TextStyle(color: Colors.grey.shade600)),
                        onTap: () => _showDetails(s),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.blue), onPressed: () => _showSupplierForm(supplier: s)),
                            IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), onPressed: () => _deleteSupplier(s['id'])),
                          ],
                        ),
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