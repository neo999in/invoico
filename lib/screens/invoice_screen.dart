import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';
import '../pdf_generator.dart';

class InvoiceScreen extends StatefulWidget {
  final Map<String, dynamic>? editInvoice;
  final List<Map<String, dynamic>>? editItems;

  const InvoiceScreen({super.key, this.editInvoice, this.editItems});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> cart = [];

  String? selectedCustomerPhone;
  final _customerNameCtrl = TextEditingController();
  final _newCustomerPhoneCtrl = TextEditingController(); // Controller for walk-in phone
  final _paidAmountCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();

  bool get isEditing => widget.editInvoice != null;

  @override
  void initState() {
    super.initState();
    _loadData();
    if (isEditing) _initEditMode();
  }

  void _initEditMode() {
    final inv = widget.editInvoice!;
    _customerNameCtrl.text = inv['customer_name'];
    selectedCustomerPhone = inv['customer_phone'] == 'N/A' ? null : inv['customer_phone'];
    _paidAmountCtrl.text = inv['paid_amount'].toString();
    _discountCtrl.text = inv['discount'].toString();

    for (var item in widget.editItems!) {
      cart.add({
        'product_id': -1,
        'product_name': item['product_name'],
        'quantity': item['quantity'],
        'price': item['price'],
        'gst_rate': item['gst_rate'],
        'line_total': item['line_total'],
      });
    }
  }

  void _loadData() async {
    final c = await DatabaseHelper.instance.getCustomers();
    final p = await DatabaseHelper.instance.getProductsWithCategory();
    if(mounted) setState(() { customers = c; products = p; });
  }

  double _calcLineTotal(double price, int qty, double gstRate) {
    double gstAmt = (price * qty) * (gstRate / 100);
    return (price * qty) + gstAmt;
  }

  void _addBulkToCart(Map<int, int> selections) {
    int addedCount = 0;
    selections.forEach((productId, qty) {
      if (qty > 0) {
        final product = products.firstWhere((p) => p['id'] == productId);
        int existingIndex = cart.indexWhere((item) => item['product_name'] == product['name']);

        if (existingIndex >= 0) {
          int newQty = cart[existingIndex]['quantity'] + qty;
          if (newQty > product['stock']) {
            _showError("Limit reached for ${product['name']}");
            newQty = product['stock'];
          }
          cart[existingIndex]['quantity'] = newQty;
          cart[existingIndex]['line_total'] = _calcLineTotal(product['price'], newQty, product['gst_rate']);
        } else {
          if (qty > product['stock']) {
            _showError("Not enough stock for ${product['name']}");
            return;
          }
          cart.add({
            'product_id': product['id'],
            'product_name': product['name'],
            'quantity': qty,
            'price': product['price'],
            'gst_rate': product['gst_rate'],
            'line_total': _calcLineTotal(product['price'], qty, product['gst_rate']),
            'stock_limit': product['stock']
          });
          addedCount++;
        }
      }
    });
    setState(() {});
    if (addedCount > 0) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Added items to cart"), backgroundColor: Colors.green));
  }

  void _updateCartQty(int index, int change) {
    setState(() {
      var item = cart[index];
      int newQty = item['quantity'] + change;
      int limit = item['stock_limit'] ?? 9999;

      if (item['stock_limit'] == null) {
        try {
          final prod = products.firstWhere((p) => p['name'] == item['product_name']);
          limit = prod['stock'];
        } catch (e) {
          limit = 9999;
        }
      }

      if (newQty > limit) {
        _showError("Max stock available: $limit");
        return;
      }

      if (newQty < 1) {
        cart.removeAt(index);
      } else {
        item['quantity'] = newQty;
        item['line_total'] = _calcLineTotal(item['price'], newQty, item['gst_rate']);
      }
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red, duration: const Duration(seconds: 2)));
  }

  double get subTotal => cart.fold(0, (sum, item) => sum + item['line_total']);
  double get discount => double.tryParse(_discountCtrl.text) ?? 0;
  double get grandTotal => subTotal - discount;

  Future<void> _processInvoice() async {
    if (cart.isEmpty) { _showError("Cart is empty!"); return; }

    // Discount validation
    if (discount > subTotal) {
      _showError("Discount cannot be greater than the Subtotal!");
      return;
    }

    double paid = double.tryParse(_paidAmountCtrl.text) ?? 0;
    double finalPaid = paid > grandTotal ? grandTotal : paid;
    double balance = grandTotal - finalPaid;
    if (balance < 0) balance = 0;

    String custName = _customerNameCtrl.text.trim();
    String custPhone = selectedCustomerPhone ?? _newCustomerPhoneCtrl.text.trim();

    if (selectedCustomerPhone != null) {
      final cust = customers.firstWhere((c) => c['phone'] == selectedCustomerPhone, orElse: () => {});
      if (cust.isNotEmpty) custName = cust['name'];
    } else if (custName.isNotEmpty && custPhone.isNotEmpty) {
      // Automatically save new walk-in customer to database
      try {
        await DatabaseHelper.instance.addCustomer({
          'name': custName,
          'phone': custPhone,
          'address': 'Added via Invoice'
        });
      } catch (e) {
        debugPrint("Customer might already exist or error: $e");
      }
    }

    if (custName.isEmpty) custName = "Walk-in Customer";
    if (custPhone.isEmpty) custPhone = "N/A";

    final invoiceData = {
      'customer_name': custName,
      'customer_phone': custPhone,
      'date': isEditing ? widget.editInvoice!['date'] : DateTime.now().toString(),
      'total_amount': grandTotal,
      'discount': discount,
      'paid_amount': finalPaid,
      'balance_due': balance
    };

    int invoiceId;
    if (isEditing) {
      await DatabaseHelper.instance.updateInvoice(widget.editInvoice!['id'], invoiceData, cart);
      invoiceId = widget.editInvoice!['id'];
    } else {
      invoiceId = await DatabaseHelper.instance.createInvoice(invoiceData, cart);
    }

    await PdfGenerator.generateAndPrint(invoiceId);
    if (mounted) Navigator.pop(context);
  }

  void _showProductPicker() {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (_) {
      return DraggableScrollableSheet(
        initialChildSize: 0.9,
        builder: (_, scrollController) => _BulkProductPickerSheet(
            products: products,
            scrollController: scrollController,
            onAddAll: (finalSelections) {
              _addBulkToCart(finalSelections);
              Navigator.pop(context);
            }
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? "Edit Invoice #${widget.editInvoice!['id']}" : "New Invoice", style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // --- CUSTOMER SELECTION CARD ---
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            const Text("Customer Details", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: "Select Existing Customer"),
                          items: customers.map((c) => DropdownMenuItem(value: c['phone'] as String, child: Text("${c['name']} (${c['phone']})"))).toList(),
                          onChanged: (val) => setState(() {
                            selectedCustomerPhone = val;
                            if(val != null) {
                              _customerNameCtrl.clear();
                              _newCustomerPhoneCtrl.clear();
                            }
                          }),
                          value: selectedCustomerPhone,
                        ),
                        if (selectedCustomerPhone == null) ...[
                          const SizedBox(height: 12),
                          // Split Name and Phone fields for Walk-ins
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _customerNameCtrl,
                                  decoration: const InputDecoration(labelText: "New Customer Name"),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _newCustomerPhoneCtrl,
                                  decoration: const InputDecoration(labelText: "Phone (Optional)"),
                                  keyboardType: TextInputType.phone,
                                ),
                              ),
                            ],
                          ),
                        ]
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // --- CART ITEMS ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Cart Items", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      onPressed: _showProductPicker,
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      label: const Text("ADD ITEMS"),
                      style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          textStyle: const TextStyle(fontWeight: FontWeight.bold)
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 8),

                if (cart.isEmpty)
                  Card(
                    color: Colors.grey.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.shopping_bag_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text("Your cart is empty", style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemCount: cart.length,
                    itemBuilder: (ctx, i) {
                      final item = cart[i];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['product_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    const SizedBox(height: 4),
                                    Text("₹${item['price']} + ${item['gst_rate'].toInt()}% GST", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                    const SizedBox(height: 4),
                                    Text("₹${item['line_total'].toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary, fontSize: 15)),
                                  ],
                                ),
                              ),
                              Container(
                                height: 36,
                                decoration: BoxDecoration(
                                    border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
                                    borderRadius: BorderRadius.circular(8),
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.05)
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove, size: 16), color: Theme.of(context).colorScheme.primary,
                                      onPressed: () => _updateCartQty(i, -1), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32),
                                    ),
                                    Container(
                                        constraints: const BoxConstraints(minWidth: 20), alignment: Alignment.center,
                                        child: Text("${item['quantity']}", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary))
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 16), color: Theme.of(context).colorScheme.primary,
                                      onPressed: () => _updateCartQty(i, 1), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () => setState(() => cart.removeAt(i)),
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                                constraints: const BoxConstraints(minWidth: 32),
                                padding: EdgeInsets.zero,
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),

          // --- BOTTOM BILLING SUMMARY ---
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]
            ),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("Subtotal", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600)),
                  Text("₹ ${subTotal.toStringAsFixed(2)}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("Discount (₹)", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600)),
                  SizedBox(
                    width: 100, height: 35,
                    child: TextField(
                      controller: _discountCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.right,
                      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      onChanged: (val) => setState(() {}),
                    ),
                  )
                ]),
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("Grand Total", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text("₹ ${grandTotal.toStringAsFixed(2)}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                ]),
                const SizedBox(height: 16),

                TextField(
                  controller: _paidAmountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Cash Received",
                    prefixIcon: const Icon(Icons.currency_rupee),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade50,
                          foregroundColor: Colors.green.shade800,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => setState(() => _paidAmountCtrl.text = grandTotal.toString()),
                        child: const Text("FULL PAY", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                        onPressed: _processInvoice,
                        child: Text(isEditing ? "UPDATE & PRINT" : "SAVE & PRINT", style: const TextStyle(letterSpacing: 1))
                    )
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _BulkProductPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  final ScrollController scrollController;
  final Function(Map<int, int>) onAddAll;
  const _BulkProductPickerSheet({required this.products, required this.scrollController, required this.onAddAll});
  @override
  State<_BulkProductPickerSheet> createState() => _BulkProductPickerSheetState();
}

class _BulkProductPickerSheetState extends State<_BulkProductPickerSheet> {
  Map<int, int> selections = {};
  String searchQuery = "";
  List<Map<String, dynamic>> filtered = [];

  @override
  void initState() { super.initState(); filtered = widget.products; }

  void _filter(String query) {
    setState(() {
      searchQuery = query;
      filtered = widget.products.where((p) => p['name'].toString().toLowerCase().contains(query.toLowerCase())).toList();
    });
  }

  int _getTotalItems() => selections.values.fold(0, (sum, qty) => sum + qty);

  @override
  Widget build(BuildContext context) {
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var p in filtered) {
      String cat = p['category_name'] ?? "Other";
      if (!grouped.containsKey(cat)) grouped[cat] = [];
      grouped[cat]!.add(p);
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Select Products", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Chip(
                label: Text("${_getTotalItems()} Selected", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                side: BorderSide.none
            )
          ],
        ),
        const SizedBox(height: 16),
        TextField(decoration: const InputDecoration(hintText: "Search items...", prefixIcon: Icon(Icons.search)), onChanged: _filter),
        const SizedBox(height: 16),

        Expanded(child: ListView(controller: widget.scrollController, children: grouped.entries.map((entry) {
          return Card(
            elevation: 0, margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              backgroundColor: Colors.grey.shade50, collapsedBackgroundColor: Colors.transparent,
              iconColor: Theme.of(context).colorScheme.primary, collapsedIconColor: Theme.of(context).colorScheme.primary,
              title: Text(entry.key, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.primary)),
              initiallyExpanded: true,
              children: entry.value.map((p) {
                int pId = p['id'];
                int currentQty = selections[pId] ?? 0;
                int stock = p['stock'];

                return Container(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text("₹${p['price']}  •  Stock: $stock", style: TextStyle(color: Colors.grey[600], fontSize: 12))
                      ])),
                      Container(height: 36, decoration: BoxDecoration(color: currentQty > 0 ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.white, border: Border.all(color: currentQty > 0 ? Theme.of(context).colorScheme.primary : Colors.grey.shade300), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.remove, size: 16), color: currentQty > 0 ? Theme.of(context).colorScheme.primary : Colors.grey, onPressed: () => setState(() { if (currentQty > 0) selections[pId] = currentQty - 1; }), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32)),
                        Container(constraints: const BoxConstraints(minWidth: 20), alignment: Alignment.center, child: Text("$currentQty", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: currentQty > 0 ? Theme.of(context).colorScheme.primary : Colors.black))),
                        IconButton(icon: const Icon(Icons.add, size: 16), color: currentQty < stock ? Theme.of(context).colorScheme.primary : Colors.grey, onPressed: () => setState(() { if (currentQty < stock) selections[pId] = currentQty + 1; }), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32)),
                      ]))
                    ])
                );
              }).toList(),
            ),
          );
        }).toList())),

        const SizedBox(height: 16),
        SizedBox(
            width: double.infinity,
            child: ElevatedButton(
                onPressed: _getTotalItems() > 0 ? () => widget.onAddAll(selections) : null,
                child: const Text("ADD TO BILL", style: TextStyle(letterSpacing: 1))
            )
        )
      ]),
    );
  }
}