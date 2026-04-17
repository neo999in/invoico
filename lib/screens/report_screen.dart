import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';
import '../pdf_generator.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _data = {};

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month; // 0 represents "Financial Year"

  // NEW: Memory variables to store the state before entering FY view
  int _lastSelectedMonth = DateTime.now().month;
  int _lastSelectedYear = DateTime.now().year;

  // Boundaries to restrict navigation
  DateTime? _minDate;
  DateTime? _maxDate;


  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  void _loadReport() async {
    setState(() => _isLoading = true);

    final db = await DatabaseHelper.instance.database;
    final res = await db.rawQuery('SELECT MIN(date) as min_date, MAX(date) as max_date FROM invoices');

    if (res.isNotEmpty && res.first['min_date'] != null) {
      _minDate = DateTime.parse(res.first['min_date'] as String);
      _maxDate = DateTime.parse(res.first['max_date'] as String);

      DateTime currentDate = DateTime.now();
      if (_selectedYear == currentDate.year && _selectedMonth == currentDate.month && _maxDate != null) {
        if (currentDate.isAfter(_maxDate!)) {
          _selectedYear = _maxDate!.year;
          _selectedMonth = _maxDate!.month;
        }
      }
    } else {
      _minDate = DateTime(DateTime.now().year, DateTime.now().month);
      _maxDate = DateTime(DateTime.now().year, DateTime.now().month);
    }

    final data = await DatabaseHelper.instance.getAdvancedReportData(_selectedYear, _selectedMonth);

    if (mounted) {
      setState(() {
        _data = data;
        _isLoading = false;
      });
    }
  }

  void _changeYear(int offset) {
    if (_minDate == null || _maxDate == null) return;

    int targetYear = _selectedYear + offset;

    if (_selectedMonth == 0) {
      int minFY = _minDate!.month >= 4 ? _minDate!.year : _minDate!.year - 1;
      int maxFY = _maxDate!.month >= 4 ? _maxDate!.year : _maxDate!.year - 1;
      if (targetYear < minFY || targetYear > maxFY) return;
    } else {
      if (targetYear < _minDate!.year) return;
      if (targetYear > _maxDate!.year) return;
    }

    setState(() {
      _selectedYear = targetYear;

      if (_selectedMonth != 0) {
        if (_selectedYear == _minDate!.year && _selectedMonth < _minDate!.month) {
          _selectedMonth = _minDate!.month;
        } else if (_selectedYear == _maxDate!.year && _selectedMonth > _maxDate!.month) {
          _selectedMonth = _maxDate!.month;
        }
      }
    });
    _loadReport();
  }

  void _changeMonth(int offset) {
    if (_minDate == null || _maxDate == null) return;

    int targetMonth = _selectedMonth;
    int targetYear = _selectedYear;

    if (targetMonth == 0) {
      // If viewing FY and user clicks month arrows, snap into calendar months
      targetMonth = offset > 0 ? 1 : 12;
    } else {
      // Normal 1 to 12 loop (skips 0 completely)
      targetMonth += offset;
      if (targetMonth > 12) {
        targetMonth = 1;
        targetYear++;
      } else if (targetMonth < 1) {
        targetMonth = 12;
        targetYear--;
      }
    }

    if (targetYear < _minDate!.year || (targetYear == _minDate!.year && targetMonth < _minDate!.month)) {
      return;
    }
    if (targetYear > _maxDate!.year || (targetYear == _maxDate!.year && targetMonth > _maxDate!.month)) {
      return;
    }

    setState(() {
      _selectedYear = targetYear;
      _selectedMonth = targetMonth;
    });

    _loadReport();
  }

  double _parse(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  String fmt(dynamic val) => "₹${_parse(val).toStringAsFixed(0)}";

  void _showFYReportDialog() async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.rawQuery('SELECT MIN(date) as min_date, MAX(date) as max_date FROM invoices');

    if (!mounted) return;

    if (res.isEmpty || res.first['min_date'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No sales data available yet.', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    DateTime minDate = DateTime.parse(res.first['min_date'] as String);
    DateTime maxDate = DateTime.parse(res.first['max_date'] as String);

    int minFY = minDate.month >= 4 ? minDate.year : minDate.year - 1;
    int maxFY = maxDate.month >= 4 ? maxDate.year : maxDate.year - 1;

    List<int> availableYears = [];
    for (int i = maxFY; i >= minFY; i--) {
      availableYears.add(i);
    }

    int selectedYear = availableYears.first;

    showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                        child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(child: Text("Export FY Report", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Generate a comprehensive PDF report covering revenue, net profit, GST breakdown, and cash flow.",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      const Text("Select Financial Year", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12)
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: selectedYear,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                            items: availableYears.map((year) {
                              return DropdownMenuItem(
                                value: year,
                                child: Text("FY $year - ${year + 1}", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => selectedYear = val);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                      child: Text("CANCEL", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        PdfGenerator.generateFinancialYearReport(selectedYear);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text("GENERATE", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    ),
                  ],
                );
              }
          );
        }
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final Color primary = Theme.of(context).colorScheme.primary;

    final kpis = _data['monthly_kpis'] ?? {};
    final profitTax = _data['monthly_profit_tax'] ?? {};
    final expenses = List<Map<String, dynamic>>.from(_data['expenses'] ?? []);
    final otherIncomes = List<Map<String, dynamic>>.from(_data['other_incomes_list'] ?? []);
    final cashFlow = _data['cash_flow'] ?? {'in': 0, 'out': 0};

    final totalRevenue = _parse(kpis['total_revenue']);
    final totalOrders = _parse(kpis['total_orders']);
    final totalDiscount = _parse(kpis['total_discount']);
    final totalPaid = _parse(kpis['total_paid']);

    final grossProfit = _parse(profitTax['total_profit']);
    final totalGst = _parse(profitTax['total_gst']);

    final totalExpenseAmount = expenses.fold(0.0, (sum, e) => sum + _parse(e['total']));
    final totalOtherIncomeAmount = otherIncomes.fold(0.0, (sum, e) => sum + _parse(e['total']));

    final trueNetProfit = grossProfit + totalOtherIncomeAmount - totalExpenseAmount;
    final totalInflow = totalRevenue + totalOtherIncomeAmount;
    final profitMargin = totalInflow > 0 ? (trueNetProfit / totalInflow) * 100 : 0.0;
    final aov = totalOrders > 0 ? (totalRevenue / totalOrders) : 0.0;

    final gstSlabs = List<Map<String, dynamic>>.from(_data['gst_slabs'] ?? []);
    final mostSelling = _data['most_selling'];
    final mostProfitable = _data['most_profitable'];
    final catStats = List<Map<String, dynamic>>.from(_data['category_stats'] ?? []);
    final trendStats = List<Map<String, dynamic>>.from(_data['trend_stats'] ?? []);
    final topCustomers = List<Map<String, dynamic>>.from(_data['top_customers'] ?? []);
    final invVal = _data['inv_value'] ?? {};
    final deadStock = List<Map<String, dynamic>>.from(_data['dead_stock'] ?? []);

    bool noActivity = totalOrders == 0 && totalExpenseAmount == 0 && totalOtherIncomeAmount == 0;
    bool isYearly = _selectedMonth == 0;

    String periodText = isYearly ? "Financial Year $_selectedYear - ${_selectedYear + 1}" : "${DateFormat('MMMM').format(DateTime(2000, _selectedMonth))} $_selectedYear";

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Business Analytics", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent),
            tooltip: "Download FY Report",
            onPressed: _showFYReportDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- TOP NAVIGATION BARS ---
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 1. Month Toggle
                  Container(
                    decoration: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.chevron_left, size: 20),
                            color: primary,
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(8),
                            onPressed: () => _changeMonth(-1)
                        ),
                        SizedBox(
                            width: 45,
                            child: Center(
                                child: Text(
                                    _selectedMonth == 0 ? "-" : DateFormat('MMM').format(DateTime(2000, _selectedMonth)),
                                    style: TextStyle(fontWeight: FontWeight.bold, color: _selectedMonth == 0 ? Colors.grey : primary, fontSize: 14)
                                )
                            )
                        ),
                        IconButton(
                            icon: const Icon(Icons.chevron_right, size: 20),
                            color: primary,
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(8),
                            onPressed: () => _changeMonth(1)
                        ),
                      ],
                    ),
                  ),

                  // 2. Year Toggle
                  Container(
                    decoration: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.chevron_left, size: 20),
                            color: primary,
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(8),
                            onPressed: () => _changeYear(-1)
                        ),
                        SizedBox(
                            width: 40,
                            child: Center(
                                child: Text("$_selectedYear", style: TextStyle(fontWeight: FontWeight.bold, color: primary, fontSize: 14))
                            )
                        ),
                        IconButton(
                            icon: const Icon(Icons.chevron_right, size: 20),
                            color: primary,
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(8),
                            onPressed: () => _changeYear(1)
                        ),
                      ],
                    ),
                  ),

                  // 3. UPDATED: Bordered FY FilterChip
                  FilterChip(
                    label: const Text("FY", style: TextStyle(fontWeight: FontWeight.bold)),
                    selected: _selectedMonth == 0,
                    onSelected: (val) {
                      if (val) {
                        // Turning FY ON: Save the current month and year
                        _lastSelectedMonth = _selectedMonth;
                        _lastSelectedYear = _selectedYear;
                        setState(() => _selectedMonth = 0);
                      } else {
                        // Turning FY OFF: Restore the saved month and year
                        setState(() {
                          _selectedMonth = _lastSelectedMonth == 0 ? DateTime.now().month : _lastSelectedMonth;
                          _selectedYear = _lastSelectedYear;
                        });
                      }
                      _loadReport();
                    },
                    selectedColor: primary.withOpacity(0.1),
                    checkmarkColor: primary,
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: _selectedMonth == 0 ? primary : Colors.grey.shade700,
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: _selectedMonth == 0 ? primary : Colors.grey.shade300,
                          width: 1.5,
                        )
                    ),
                  )
                ],
              ),
            ),
            if (noActivity)
              Padding(
                padding: const EdgeInsets.only(top: 80.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.insights, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text("No activity in $periodText", style: const TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle("Overview: $periodText"),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        mainAxisExtent: 75,
                      ),
                      itemCount: 6,
                      itemBuilder: (context, index) {
                        final cards = [
                          _buildKpiCard("Total Revenue", fmt(totalRevenue), Icons.account_balance_wallet, Colors.blue.shade700),
                          _buildKpiCard("Net Profit", fmt(trueNetProfit), Icons.trending_up, trueNetProfit >= 0 ? Colors.green.shade600 : Colors.red.shade600),
                          _buildKpiCard("Profit Margin", "${profitMargin.toStringAsFixed(1)}%", Icons.pie_chart, trueNetProfit >= 0 ? Colors.teal.shade600 : Colors.red.shade600),
                          _buildKpiCard("Total Orders", totalOrders.toStringAsFixed(0), Icons.receipt_long, Colors.purple.shade500),
                          _buildKpiCard("Avg Order Value", fmt(aov), Icons.shopping_bag, Colors.orange.shade600),
                          _buildKpiCard("Discounts Given", fmt(totalDiscount), Icons.loyalty, Colors.red.shade400),
                        ];
                        return cards[index];
                      },
                    ),
                    const SizedBox(height: 12),

                    _buildSectionTitle("Finance Health & Taxes"),
                    _buildDebtRatioBar(_parse(kpis['total_paid']), _parse(kpis['total_due'])),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("GST Collected", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  Text("Slab-wise breakdown for tax filing.", style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                                ],
                              ),
                              Text(fmt(totalGst), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 18)),
                            ],
                          ),
                          if (gstSlabs.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade200),
                                  borderRadius: BorderRadius.circular(8)
                              ),
                              child: Table(
                                columnWidths: const {
                                  0: FlexColumnWidth(1),
                                  1: FlexColumnWidth(2),
                                  2: FlexColumnWidth(2),
                                },
                                children: [
                                  TableRow(
                                      decoration: BoxDecoration(color: Colors.grey.shade50),
                                      children: [
                                        _tableHeader("Slab"),
                                        _tableHeader("Sales Amount", align: TextAlign.right),
                                        _tableHeader("Tax Amount", align: TextAlign.right),
                                      ]
                                  ),
                                  ...gstSlabs.map((s) => TableRow(
                                      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
                                      children: [
                                        _tableCell("${_parse(s['slab']).toInt()}%", bold: true),
                                        _tableCell(fmt(s['total_sales']), align: TextAlign.right),
                                        _tableCell(fmt(s['tax_collected']), align: TextAlign.right, color: Colors.redAccent),
                                      ]
                                  ))
                                ],
                              ),
                            )
                          ]
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    _buildSectionTitle(isYearly ? "Financial Year Trends" : "Recent Sales Trends"),
                    _buildCustomBarChart(trendStats, isYearly),
                    const SizedBox(height: 24),

                    if (topCustomers.isNotEmpty) ...[
                      _buildSectionTitle("Top Loyal Customers"),
                      Card(
                        color: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: topCustomers.length,
                          separatorBuilder: (_,__) => const Divider(height: 1, indent: 60),
                          itemBuilder: (ctx, i) {
                            final c = topCustomers[i];
                            return ListTile(
                              leading: CircleAvatar(backgroundColor: primary.withOpacity(0.1), child: Text("${i+1}", style: TextStyle(color: primary, fontWeight: FontWeight.bold))),
                              title: Text(c['customer_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("${c['orders']} Orders"),
                              trailing: Text(fmt(c['spent']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green)),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    _buildSectionTitle("Product Performance"),
                    Row(
                      children: [
                        _buildHighlightCard("Most Sold", mostSelling?['product_name'] ?? "N/A", "${mostSelling?['qty'] ?? 0} units", Colors.blue),
                        const SizedBox(width: 12),
                        _buildHighlightCard("Top Earner", mostProfitable?['product_name'] ?? "N/A", fmt(mostProfitable?['profit']), Colors.green),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (catStats.isNotEmpty) ...[
                      Card(
                        color: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        clipBehavior: Clip.antiAlias,
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: catStats.length + 1,
                          separatorBuilder: (ctx, i) {
                            if (i == catStats.length - 1) return const SizedBox();
                            return const Divider(height: 1);
                          },
                          itemBuilder: (ctx, i) {
                            if (i == catStats.length) {
                              return Column(
                                children: [
                                  Divider(height: 1, color: Colors.grey.shade400),
                                  Container(
                                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text("Total Profit from Sales", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        Text(fmt(grossProfit), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: grossProfit >= 0 ? Colors.green : Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }

                            final cat = catStats[i];
                            double sales = _parse(cat['sales']);
                            double profit = _parse(cat['profit']);
                            double gst = _parse(cat['gst_collected']);
                            double avgBuy = _parse(cat['avg_buy_price']);
                            double avgSale = _parse(cat['avg_sale_price']);

                            Color textColor = sales > 0 ? Colors.black87 : Colors.grey.shade400;

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("${cat['category'] ?? 'Other'} (${_parse(cat['product_count']).toInt()} products)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
                                        const SizedBox(height: 4),
                                        Text("Sales: ${fmt(sales)} (${_parse(cat['total_qty_sold']).toInt()} units)", style: TextStyle(color: sales > 0 ? Colors.grey.shade700 : Colors.grey.shade400, fontSize: 12)),
                                        const SizedBox(height: 2),
                                        Text("Avg Buy: ${fmt(avgBuy)} | Avg Sell: ${fmt(avgSale)}", style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text("Profit: ${fmt(profit)}", style: TextStyle(fontWeight: FontWeight.bold, color: sales == 0 ? Colors.grey.shade400 : (profit >= 0 ? Colors.green : Colors.red), fontSize: 13)),
                                        const SizedBox(height: 2),
                                        Text("GST: ${fmt(gst)}", style: TextStyle(fontWeight: FontWeight.bold, color: sales == 0 ? Colors.grey.shade300 : Colors.deepOrange.shade400, fontSize: 11)),
                                      ]
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    _buildSectionTitle("Cash Flow Summary"),
                    Row(
                        children: [
                          _buildCard("Money In", fmt(cashFlow['in']), Icons.south_west, Colors.teal),
                          const SizedBox(width: 12),
                          _buildCard("Money Out", fmt(cashFlow['out']), Icons.north_east, Colors.red),
                        ]
                    ),
                    const SizedBox(height: 16),

                    if (expenses.isNotEmpty) ...[
                      _buildExpenseBar(expenses),
                      const SizedBox(height: 16),
                    ],

                    if (otherIncomes.isNotEmpty) ...[
                      _buildOtherIncomeBar(otherIncomes),
                      const SizedBox(height: 24),
                    ],

                    _buildSectionTitle("Inventory valuation"),
                    Row(
                        children: [
                          _buildCard("Capital invested", fmt(invVal['capital']), Icons.inventory_2, Colors.indigo),
                          const SizedBox(width: 12),
                          _buildCard("Potential revenue", fmt(invVal['revenue']), Icons.attach_money, Colors.green),
                        ]
                    ),
                    const SizedBox(height: 16),

                    if (deadStock.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.orange.shade200)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                                const SizedBox(width: 8),
                                const Text("Dead Stock", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                                const Spacer(),
                                Text("${deadStock.length} items", style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold))
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text("No sales in the last 30 days.", style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8, runSpacing: 8,
                              children: deadStock.map((s) => Chip(
                                label: Text("${s['name']} (${s['stock']})", style: const TextStyle(fontSize: 11, color: Colors.deepOrange)),
                                backgroundColor: Colors.white,
                                side: BorderSide.none,
                                padding: EdgeInsets.zero,
                              )).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                    ] else ...[
                      const SizedBox(height: 24),
                    ]
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Widget Helpers
  Widget _tableHeader(String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(text, textAlign: align, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600, fontSize: 12)),
    );
  }

  Widget _tableCell(String text, {TextAlign align = TextAlign.left, bool bold = false, Color color = Colors.black87}) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(text, textAlign: align, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color, fontSize: 12)),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black87)),
    );
  }

  Widget _buildKpiCard(String title, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 6),
          Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: val.contains('-') ? Colors.red : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildHighlightCard(String title, String val, String sub, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.2))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(sub, style: TextStyle(color: color.withOpacity(0.8), fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(String title, String val, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]
        ),
      ),
    );
  }

  Widget _buildDebtRatioBar(double paid, double due) {
    double total = paid + due;
    if (total == 0) return const SizedBox();

    int paidFlex = (paid / total * 100).toInt();
    int dueFlex = 100 - paidFlex;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Collected: ${fmt(paid)} ($paidFlex%)", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
              Text("Unpaid: ${fmt(due)} ($dueFlex%)", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 12, width: double.infinity,
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: [
                  if (paidFlex > 0) Expanded(flex: paidFlex, child: Container(color: Colors.green)),
                  if (dueFlex > 0) Expanded(flex: dueFlex, child: Container(color: Colors.red)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomBarChart(List<Map<String, dynamic>> stats, bool isYearly) {
    if (stats.isEmpty) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: const Text("No trend data available", style: TextStyle(color: Colors.grey)),
      );
    }

    int maxItems = isYearly ? 12 : 7;
    List<Map<String, dynamic>> chartData = stats.length > maxItems
        ? stats.sublist(stats.length - maxItems)
        : stats;

    double maxVal = 1;
    for (var d in chartData) {
      double sales = _parse(d['sales']);
      double profit = _parse(d['profit']);
      if (sales > maxVal) maxVal = sales;
      if (profit > maxVal) maxVal = profit;
    }

    return Container(
      height: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: chartData.map((d) {
          double sales = _parse(d['sales']);
          double profit = _parse(d['profit']);

          double sHeight = (sales / maxVal) * 120;
          double pHeight = (profit / maxVal) * 120;

          if (sHeight < 2 && sales > 0) sHeight = 5;
          if (pHeight < 2 && profit > 0) pHeight = 5;

          DateTime parsedDate = isYearly
              ? DateTime.parse("${d['date_str']}-01")
              : DateTime.parse(d['date_str']);

          String label = isYearly ? DateFormat('MMM').format(parsedDate) : DateFormat('dd MMM').format(parsedDate);

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(width: 8, height: sHeight, decoration: BoxDecoration(color: Colors.blue.shade400, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))),
                  const SizedBox(width: 2),
                  Container(width: 8, height: pHeight, decoration: BoxDecoration(color: Colors.green.shade400, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))),
                ],
              ),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildExpenseBar(List<Map<String, dynamic>> expenses) {
    final colors = [Colors.red, Colors.orange, Colors.purple, Colors.blue, Colors.teal, Colors.brown];
    double totalExp = expenses.fold(0.0, (sum, e) => sum + _parse(e['total']));

    if (totalExp == 0) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Expense Breakdown", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text("Total: ${fmt(totalExp)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 12, width: double.infinity,
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: expenses.asMap().entries.map((e) {
                  int flex = ((_parse(e.value['total']) / totalExp) * 100).toInt();
                  if (flex == 0) flex = 1;
                  return Expanded(flex: flex, child: Container(color: colors[e.key % colors.length]));
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12, runSpacing: 8,
            children: expenses.asMap().entries.map((e) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[e.key % colors.length], shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text("${e.value['title']} (${fmt(e.value['total'])})", style: const TextStyle(fontSize: 12)),
                ],
              );
            }).toList(),
          )
        ],
      ),
    );
  }

  Widget _buildOtherIncomeBar(List<Map<String, dynamic>> incomes) {
    final colors = [Colors.green, Colors.teal, Colors.lightGreen, Colors.blue, Colors.cyan, Colors.indigo];
    double totalInc = incomes.fold(0.0, (sum, e) => sum + _parse(e['total']));

    if (totalInc == 0) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Other Income Breakdown", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text("Total: ${fmt(totalInc)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 12, width: double.infinity,
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: incomes.asMap().entries.map((e) {
                  int flex = ((_parse(e.value['total']) / totalInc) * 100).toInt();
                  if (flex == 0) flex = 1;
                  return Expanded(flex: flex, child: Container(color: colors[e.key % colors.length]));
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12, runSpacing: 8,
            children: incomes.asMap().entries.map((e) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[e.key % colors.length], shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text("${e.value['title']} (${fmt(e.value['total'])})", style: const TextStyle(fontSize: 12)),
                ],
              );
            }).toList(),
          )
        ],
      ),
    );
  }
}