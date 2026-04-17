import 'package:flutter/material.dart';
import '../database_helper.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  List<Map<String, dynamic>> categories = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() async {
    final data = await DatabaseHelper.instance.getCategories(); // Now includes product_count
    setState(() => categories = data);
  }

  void _showForm({Map<String, dynamic>? category}) {
    final nameCtrl = TextEditingController(text: category?['name']);
    double selectedGst = category?['gst_rate'] ?? 0.0;
    bool isEdit = category != null;

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => StatefulBuilder(
            builder: (context, setModalState) {
              return Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(isEdit ? "Edit Category" : "Add Category", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),

                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Category Name", prefixIcon: Icon(Icons.category))),
                  const SizedBox(height: 20),

                  const Text("Select Default GST Rate:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  // ADDED: GST Button Selections
                  Wrap(
                    spacing: 8,
                    children: [0.0, 5.0, 12.0, 18.0, 28.0].map((rate) => ChoiceChip(
                      label: Text("${rate.toInt()}%"),
                      selected: selectedGst == rate,
                      selectedColor: Colors.indigo.shade100,
                      checkmarkColor: Colors.indigo,
                      onSelected: (selected) {
                        setModalState(() => selectedGst = rate);
                      },
                    )).toList(),
                  ),

                  const SizedBox(height: 24),
                  SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () async {
                    if(nameCtrl.text.isEmpty) return;
                    try {
                      if (isEdit) {
                        await DatabaseHelper.instance.updateCategory(category['id'], nameCtrl.text, selectedGst);
                      } else {
                        await DatabaseHelper.instance.addCategory(nameCtrl.text, selectedGst);
                      }
                      if(mounted) Navigator.pop(context); _refresh();
                    } catch(e) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Category exists!"), backgroundColor: Colors.red));
                    }
                  }, child: const Text("SAVE")))
                ]),
              );
            }
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Categories", style: TextStyle(fontWeight: FontWeight.bold))),
      floatingActionButton: FloatingActionButton(onPressed: () => _showForm(), backgroundColor: Colors.indigo, child: const Icon(Icons.add, color: Colors.white)),
      body: categories.isEmpty
          ? Center(child: Text("No categories found", style: TextStyle(color: Colors.grey.shade600)))
          : ListView.separated(
        padding: const EdgeInsets.all(16), itemCount: categories.length, separatorBuilder: (_,__) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final cat = categories[i];
          bool isOther = cat['name'] == 'Other';
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(backgroundColor: Colors.indigo.shade50, child: const Icon(Icons.category, color: Colors.indigo)),
              title: Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              // ADDED: Product Count Display
              subtitle: Text("GST: ${cat['gst_rate']}%  •  Products: ${cat['product_count']}", style: TextStyle(color: Colors.grey.shade700)),
              trailing: isOther ? null : Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showForm(category: cat)),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () async {
                  if (cat['product_count'] > 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot delete! Reassign products first."), backgroundColor: Colors.red));
                    return;
                  }
                  await DatabaseHelper.instance.deleteCategory(cat['id']); _refresh();
                }),
              ]),
            ),
          );
        },
      ),
    );
  }
}
