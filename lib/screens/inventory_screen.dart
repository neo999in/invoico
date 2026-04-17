import 'package:flutter/material.dart';
import '../database_helper.dart';
import 'category_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> filteredProducts = [];
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> suppliers = [];

  final TextEditingController _searchCtrl = TextEditingController();
  bool showLowStockOnly = false;
  int? selectedCategoryFilter;

  @override
  void initState() {
    super.initState();
    _refresh();
    _searchCtrl.addListener(_applyFilters);
  }

  void _applyFilters() {
    setState(() {
      filteredProducts = products.where((p) {
        bool matchesSearch = p['name'].toString().toLowerCase().contains(_searchCtrl.text.toLowerCase());
        bool matchesLowStock = !showLowStockOnly || (p['stock'] <= (p['low_stock_limit'] ?? 5));
        bool matchesCategory = selectedCategoryFilter == null || p['category_id'] == selectedCategoryFilter;
        return matchesSearch && matchesLowStock && matchesCategory;
      }).toList();
    });
  }

  void _refresh() async {
    final pData = await DatabaseHelper.instance.getProductsWithCategory();
    final cData = await DatabaseHelper.instance.getCategories();
    final sData = await DatabaseHelper.instance.getSuppliers();
    if(mounted) {
      setState(() { products = pData; categories = cData; suppliers = sData; });
      _applyFilters();
    }
  }

  void _showAddStockDialog(Map<String, dynamic> product) {
    int qty = 1;
    String? selectedSupplier;
    final customSupplierCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final paidCtrl = TextEditingController();

    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text("Buy Stock: ${product['name']}"),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: "Select Supplier"),
                  items: suppliers.map((s) => DropdownMenuItem(value: s['name'] as String, child: Text(s['name']))).toList(),
                  onChanged: (val) => setDialogState(() {
                    selectedSupplier = val;
                    customSupplierCtrl.clear();
                  }),
                  value: selectedSupplier,
                ),
                const SizedBox(height: 10),
                if (selectedSupplier == null)
                  TextField(
                      controller: customSupplierCtrl,
                      decoration: const InputDecoration(labelText: "Or Enter Custom Supplier Name")
                  ),
                const SizedBox(height: 10),
                TextField(
                    controller: costCtrl,
                    decoration: const InputDecoration(labelText: "Total Bill Cost"),
                    keyboardType: TextInputType.number
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: paidCtrl,
                    decoration: const InputDecoration(
                        labelText: "Amount Paid Now",
                        hintText: "Leave blank if fully unpaid"
                    ),
                    keyboardType: TextInputType.number
                ),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setDialogState(() { if(qty > 1) qty--; })),
                  Text(" $qty ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                  IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setDialogState(() => qty++)),
                ]),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCEL")
              ),
              ElevatedButton(
                  onPressed: () async {
                    double totalCost = double.tryParse(costCtrl.text) ?? 0;
                    double paidAmount = double.tryParse(paidCtrl.text) ?? 0;

                    String finalSupplier = selectedSupplier ?? customSupplierCtrl.text.trim();
                    if (finalSupplier.isEmpty) finalSupplier = "Unknown Supplier";

                    // 1. Auto-create new supplier in Contacts
                    if (selectedSupplier == null && customSupplierCtrl.text.trim().isNotEmpty) {
                      try {
                        await DatabaseHelper.instance.addSupplier({
                          'name': finalSupplier,
                          'phone': '',
                          'address': 'Added via Inventory Purchase'
                        });
                      } catch (e) {
                        debugPrint("Supplier already exists or error: $e");
                      }
                    }

                    if (paidAmount > totalCost) paidAmount = totalCost;

                    // 2. Calculate Weighted Average Buy Price
                    int oldStock = product['stock'] ?? 0;
                    double oldPrice = product['purchase_price'] ?? 0.0;
                    double newAvgPrice = oldPrice;

                    if ((oldStock + qty) > 0) {
                      newAvgPrice = ((oldStock * oldPrice) + totalCost) / (oldStock + qty);
                    }

                    // 3. Log the stock purchase history
                    await DatabaseHelper.instance.addStock(
                        product['name'], qty, totalCost, paidAmount, finalSupplier
                    );

                    // FIXED: Create a STRICT map with only valid product columns to prevent SQLite crashes
                    final safeProductUpdate = {
                      'id': product['id'],
                      'name': product['name'],
                      'price': product['price'],
                      'purchase_price': double.parse(newAvgPrice.toStringAsFixed(2)),
                      'stock': oldStock + qty,
                      'gst_rate': product['gst_rate'],
                      'low_stock_limit': product['low_stock_limit'],
                      'category_id': product['category_id'],
                    };

                    // 4. Update the product record with new average price & stock
                    await DatabaseHelper.instance.updateProduct(safeProductUpdate);

                    // 5. Automatically log debt to payables if partially paid
                    double debt = totalCost - paidAmount;
                    if (debt > 0) {
                      await DatabaseHelper.instance.addPayable({
                        'title': 'Stock from $finalSupplier: ${product['name']} (x$qty)',
                        'amount': debt,
                        'balance_due': debt,
                        'date': DateTime.now().toString()
                      });
                    }

                    if (mounted) Navigator.pop(context);
                    _refresh();
                  },
                  child: const Text("SAVE")
              )
            ],
          ),
        )
    );
  }

  void _showRemoveStockDialog(Map<String, dynamic> product) {
    int qty = 1;
    final reasonCtrl = TextEditingController();
    showDialog(context: context, builder: (_) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text("Adjust Stock: ${product['name']}"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: "Reason (e.g. Damaged)")),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setDialogState(() { if(qty > 1) qty--; })),
            Text(" $qty ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
            IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setDialogState(() { if(qty < product['stock']) qty++; })),
          ]),
        ]),
        actions: [ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () async { await DatabaseHelper.instance.removeStock(product['name'], qty, reasonCtrl.text); if(mounted) Navigator.pop(context); _refresh(); }, child: const Text("REMOVE"))],
      ),
    ));
  }

  void _showHistory(Map<String, dynamic> product) async {
    final history = await DatabaseHelper.instance.getProductHistory(product['name']);
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text("History: ${product['name']}"),
      content: SizedBox(
        width: double.maxFinite,
        child: history.isEmpty ? const Text("No history found.") : ListView.separated(
          shrinkWrap: true, separatorBuilder: (_,__) => const Divider(height: 1), itemCount: history.length,
          itemBuilder: (ctx, i) {
            final h = history[i];
            bool isSale = h['type'] == 'SALE';
            bool isAdj = !isSale && h['ref'].toString().startsWith("Adj");
            bool isBuy = !isSale && !isAdj;
            Color color = isSale ? Colors.red : (isAdj ? Colors.orange : Colors.green);
            String sign = isSale || (isAdj && h['quantity'] < 0) ? "-" : "+";
            return ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: Icon(isSale ? Icons.outbox : (isAdj ? Icons.tune : Icons.add_shopping_cart), color: color, size: 20),
              title: Text(h['ref'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(h['date'].toString().substring(0, 10)),
              trailing: Text("$sign${h['quantity'].abs()} ${isBuy && h['amount']!=null ? '(₹${h['amount']})' : ''}", style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: const Text("CLOSE"))],
    ));
  }

  void _showProductDialog({Map<String, dynamic>? product}) {
    final nameCtrl = TextEditingController(text: product?['name']);
    final priceCtrl = TextEditingController(text: product?['price']?.toString());
    final purchasePriceCtrl = TextEditingController(text: product?['purchase_price']?.toString());
    final stockCtrl = TextEditingController(text: product?['stock']?.toString());
    final lowStockCtrl = TextEditingController(text: product?['low_stock_limit']?.toString() ?? '5');
    int? selectedCatId = product?['category_id'] ?? (categories.isNotEmpty ? categories.first['id'] : null);
    double selectedGst = product?['gst_rate'] ?? 0.0;

    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) {
      return StatefulBuilder(builder: (context, setModalState) {
        bool isManualGst = selectedCatId != null && (categories.firstWhere((c) => c['id'] == selectedCatId, orElse: () => {})['gst_rate'] == -1.0);
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(product == null ? "Add Product" : "Edit Product", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ActionChip(avatar: const Icon(Icons.settings, size: 16), label: const Text("Categories"), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoryScreen())).then((_) => _refresh()))
            ]),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Product Name")),
            const SizedBox(height: 12),
            Row(children: [ Expanded(child: TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: "Sell Price"), keyboardType: TextInputType.number)), const SizedBox(width: 12), Expanded(child: TextField(controller: purchasePriceCtrl, decoration: const InputDecoration(labelText: "Buy Price"), keyboardType: TextInputType.number)), ]),
            const SizedBox(height: 12),
            Row(children: [ Expanded(child: TextField(controller: stockCtrl, decoration: const InputDecoration(labelText: "Stock"), keyboardType: TextInputType.number)), const SizedBox(width: 12), Expanded(child: TextField(controller: lowStockCtrl, decoration: const InputDecoration(labelText: "Low Stock Alert At"), keyboardType: TextInputType.number)), ]),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: selectedCatId, decoration: const InputDecoration(labelText: "Category"),
              items: categories.map((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['name']))).toList(),
              onChanged: (val) { setModalState(() { selectedCatId = val; final cat = categories.firstWhere((c) => c['id'] == val); if (cat['gst_rate'] != -1.0) selectedGst = cat['gst_rate']; }); },
            ),
            if (isManualGst) ...[
              const SizedBox(height: 16),
              const Text("Select GST Rate:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [0.0, 5.0, 12.0, 18.0].map((r) => ChoiceChip(label: Text("${r.toInt()}%"), selected: selectedGst == r, onSelected: (b) => setModalState(() => selectedGst = r))).toList())
            ],
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
              if (nameCtrl.text.isEmpty) return;
              final data = {'name': nameCtrl.text, 'price': double.tryParse(priceCtrl.text) ?? 0, 'purchase_price': double.tryParse(purchasePriceCtrl.text) ?? 0, 'stock': int.tryParse(stockCtrl.text) ?? 0, 'gst_rate': selectedGst, 'low_stock_limit': int.tryParse(lowStockCtrl.text) ?? 5, 'category_id': selectedCatId};
              if (product == null) await DatabaseHelper.instance.addProduct(data); else { data['id'] = product['id']; await DatabaseHelper.instance.updateProduct(data); }
              if(mounted) Navigator.pop(context); _refresh();
            }, child: const Text("SAVE PRODUCT")))
          ]),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Inventory", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 0),
            child: TextButton.icon(
              icon: const Icon(Icons.category, color: Colors.indigo),
              label: const Text("Categories", style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoryScreen())).then((_) => _refresh()),
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showProductDialog(), child: const Icon(Icons.add)),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            color: Colors.white,
            child: Column(
              children: [
                Row(children: [
                  Expanded(child: TextField(controller: _searchCtrl, decoration: const InputDecoration(hintText: "Search items...", prefixIcon: Icon(Icons.search)))),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: const Icon(Icons.warning_amber_rounded, size: 20),
                    selected: showLowStockOnly,
                    onSelected: (val) { setState(() => showLowStockOnly = val); _applyFilters(); },
                    selectedColor: Colors.red.shade100, checkmarkColor: Colors.red,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ]),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    ChoiceChip(label: const Text("All"), selected: selectedCategoryFilter == null, onSelected: (b) { setState(() => selectedCategoryFilter = null); _applyFilters(); }),
                    const SizedBox(width: 8),
                    ...categories.map((c) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(c['name']), selected: selectedCategoryFilter == c['id'], onSelected: (b) { setState(() => selectedCategoryFilter = b ? c['id'] : null); _applyFilters(); })))
                  ]),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: filteredProducts.length,
              separatorBuilder: (_,__) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = filteredProducts[index];
                bool isLow = item['stock'] <= (item['low_stock_limit'] ?? 5);

                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: isLow ? Colors.red.shade300 : Colors.grey.shade200, width: isLow ? 1.5 : 1)),
                  child: ExpansionTile(
                    shape: const Border(),
                    leading: Container(
                      width: 45, height: 45,
                      decoration: BoxDecoration(color: isLow ? Colors.red.shade50 : Colors.indigo.shade50, borderRadius: BorderRadius.circular(12)),
                      child: Center(child: Text("${item['stock']}", style: TextStyle(fontWeight: FontWeight.bold, color: isLow ? Colors.red : Colors.indigo, fontSize: 16))),
                    ),
                    title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text("Buy: ₹${item['purchase_price']} • Sell: ₹${item['price']}", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    children: [
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _actionBtn(Icons.history, "History", Colors.blue, () => _showHistory(item)),
                            _actionBtn(Icons.add_shopping_cart, "Buy", Colors.green, () => _showAddStockDialog(item)),
                            _actionBtn(Icons.tune, "Adj", Colors.orange, () => _showRemoveStockDialog(item)),
                            _actionBtn(Icons.edit, "Edit", Colors.indigo, () => _showProductDialog(product: item)),
                            _actionBtn(Icons.delete_outline, "Del", Colors.red, () async { await DatabaseHelper.instance.deleteProduct(item['id']); _refresh(); }),
                          ],
                        ),
                      )
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}