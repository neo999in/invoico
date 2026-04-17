import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'database_helper.dart';

class PdfGenerator {

  // --- EXISTING METHOD: SINGLE INVOICE PRINTING ---
  static Future<void> generateAndPrint(int invoiceId) async {
    final invoices = await DatabaseHelper.instance.getAllInvoices();
    final invoice = invoices.firstWhere((i) => i['id'] == invoiceId, orElse: () => {});

    if (invoice.isEmpty) return;

    final items = await DatabaseHelper.instance.getInvoiceItems(invoiceId);
    final user = await DatabaseHelper.instance.getUser();

    String shopName = user?['shop_name'] ?? "MY SHOP";
    String shopPhone = user?['phone'] ?? "";
    String shopAddress = user?['address'] ?? "";
    String custName = invoice['customer_name'] ?? "Unknown";

    double grandTotal = invoice['total_amount'];
    double discount = invoice['discount'] ?? 0.0;
    double paidAmount = invoice['paid_amount'];
    double balance = invoice['balance_due'];

    double subTotal = grandTotal + discount;

    DateTime date = DateTime.parse(invoice['date']);

    final font = await PdfGoogleFonts.notoSansDevanagariRegular();
    final pdf = pw.Document();

    pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(10),
        build: (pw.Context context) {
          String fmt(double amount) => NumberFormat.currency(symbol: 'Rs. ', locale: 'en_IN', decimalDigits: 2).format(amount);

          return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(shopName.toUpperCase(), style: pw.TextStyle(font: font, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                if (shopAddress.isNotEmpty) pw.Text(shopAddress, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: font, fontSize: 10)),
                if (shopPhone.isNotEmpty) pw.Text("Tel: $shopPhone", style: pw.TextStyle(font: font, fontSize: 10)),
                pw.SizedBox(height: 10),
                pw.Divider(borderStyle: pw.BorderStyle.dashed),

                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text("Inv #: $invoiceId", style: pw.TextStyle(font: font, fontSize: 10)),
                  pw.Text(DateFormat('dd/MM/yy HH:mm').format(date), style: pw.TextStyle(font: font, fontSize: 10)),
                ]),
                pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text("Cust: $custName", style: pw.TextStyle(font: font, fontSize: 10))),

                pw.Divider(borderStyle: pw.BorderStyle.dashed),

                pw.Table(
                    columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(2)},
                    children: [
                      pw.TableRow(children: [
                        pw.Text("Item", style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text("Qty", textAlign: pw.TextAlign.center, style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text("Total", textAlign: pw.TextAlign.right, style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      ]),
                      pw.TableRow(children: [pw.SizedBox(height: 5), pw.SizedBox(height: 5), pw.SizedBox(height: 5)]),
                      ...items.map((item) => pw.TableRow(children: [
                        pw.Text(item['product_name'], style: pw.TextStyle(font: font, fontSize: 10)),
                        pw.Text("${item['quantity']}", textAlign: pw.TextAlign.center, style: pw.TextStyle(font: font, fontSize: 10)),
                        pw.Text((item['line_total'] as double).toStringAsFixed(2), textAlign: pw.TextAlign.right, style: pw.TextStyle(font: font, fontSize: 10)),
                      ]))
                    ]
                ),

                pw.SizedBox(height: 10),
                pw.Divider(borderStyle: pw.BorderStyle.dashed),

                if (discount > 0) ...[
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text("Subtotal:", style: pw.TextStyle(font: font, fontSize: 10)),
                    pw.Text(fmt(subTotal), style: pw.TextStyle(font: font, fontSize: 10)),
                  ]),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text("Discount:", style: pw.TextStyle(font: font, fontSize: 10)),
                    pw.Text("- ${fmt(discount)}", style: pw.TextStyle(font: font, fontSize: 10)),
                  ]),
                  pw.Divider(borderStyle: pw.BorderStyle.dotted),
                ],

                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text("TOTAL", style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  pw.Text(fmt(grandTotal), style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold, fontSize: 14)),
                ]),

                pw.SizedBox(height: 5),

                if (balance <= 0) ...[
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text("Status:", style: pw.TextStyle(font: font, fontSize: 10)),
                    pw.Text("PAID", style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold)),
                  ]),
                ] else ...[
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text("Paid:", style: pw.TextStyle(font: font, fontSize: 10)),
                    pw.Text(fmt(paidAmount), style: pw.TextStyle(font: font, fontSize: 10)),
                  ]),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text("Due:", style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold)),
                    pw.Text(fmt(balance), style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold)),
                  ]),
                ],

                pw.SizedBox(height: 20),
                pw.Text("THANK YOU!", style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold)),
              ]
          );
        }
    ));

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  // --- NEW METHOD: COMPREHENSIVE FY REPORT ---
  static Future<void> generateFinancialYearReport(int startYear) async {
    final db = await DatabaseHelper.instance.database;
    final user = await DatabaseHelper.instance.getUser();

    String shopName = user?['shop_name'] ?? "MY SHOP";
    String shopAddress = user?['address'] ?? "";
    String fyRange = "FY $startYear - ${startYear + 1}";

    String startDate = '$startYear-04-01 00:00:00';
    String endDate = '${startYear + 1}-03-31 23:59:59';

    // 1. Invoices KPIs
    final kpiRes = await db.rawQuery('''
      SELECT 
        COUNT(id) as total_orders,
        IFNULL(SUM(total_amount), 0) as total_revenue, 
        IFNULL(SUM(paid_amount), 0) as total_paid,
        IFNULL(SUM(discount), 0) as total_discount 
      FROM invoices 
      WHERE date >= '$startDate' AND date <= '$endDate'
    ''');

    double totalRevenue = (kpiRes.first['total_revenue'] as num?)?.toDouble() ?? 0.0;
    double totalPaid = (kpiRes.first['total_paid'] as num?)?.toDouble() ?? 0.0;
    double totalDiscount = (kpiRes.first['total_discount'] as num?)?.toDouble() ?? 0.0;
    int totalOrders = (kpiRes.first['total_orders'] as int?) ?? 0;

    double aov = totalOrders > 0 ? (totalRevenue / totalOrders) : 0.0;

    // 2. Gross Profit
    final profitRes = await db.rawQuery('''
      SELECT IFNULL(SUM((ii.price - IFNULL(ii.purchase_price, 0)) * ii.quantity), 0) as gross_profit
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE i.date >= '$startDate' AND i.date <= '$endDate'
    ''');
    double grossProfit = (profitRes.first['gross_profit'] as num?)?.toDouble() ?? 0.0;

    // 3. Expenses & Other Income & Purchases
    final expRes = await db.rawQuery("SELECT IFNULL(SUM(amount), 0) as t FROM expenses WHERE date >= '$startDate' AND date <= '$endDate'");
    final incRes = await db.rawQuery("SELECT IFNULL(SUM(amount), 0) as t FROM other_incomes WHERE date >= '$startDate' AND date <= '$endDate'");
    final purRes = await db.rawQuery("SELECT IFNULL(SUM(cost), 0) as t FROM purchases WHERE date >= '$startDate' AND date <= '$endDate'");

    double totalExp = (expRes.first['t'] as num?)?.toDouble() ?? 0.0;
    double totalInc = (incRes.first['t'] as num?)?.toDouble() ?? 0.0;
    double totalPurchases = (purRes.first['t'] as num?)?.toDouble() ?? 0.0;

    // 4. Advanced Math
    double netProfit = grossProfit + totalInc - totalExp;
    double totalInflowForMargin = totalRevenue + totalInc;
    double profitMargin = totalInflowForMargin > 0 ? (netProfit / totalInflowForMargin) * 100 : 0.0;

    double moneyIn = totalPaid + totalInc;
    double moneyOut = totalExp + totalPurchases;
    double netCashFlow = moneyIn - moneyOut;

    // 5. GST Breakdown
    final gstSlabs = await db.rawQuery('''
      SELECT 
        IFNULL(ii.gst_rate, 0) as slab, 
        IFNULL(SUM(ii.line_total), 0) as slab_sales, 
        IFNULL(SUM(ii.price * ii.quantity * (IFNULL(ii.gst_rate, 0)/100.0)), 0) as tax_amount
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE i.date >= '$startDate' AND i.date <= '$endDate'
      GROUP BY slab
      ORDER BY slab ASC
    ''');

    double totalGstAmount = 0.0;
    for (var s in gstSlabs) {
      totalGstAmount += (s['tax_amount'] as num?)?.toDouble() ?? 0.0;
    }

    final font = await PdfGoogleFonts.notoSansDevanagariRegular();
    final fontBold = await PdfGoogleFonts.notoSansDevanagariBold();
    final pdf = pw.Document();

    String fmt(double amount) => NumberFormat.currency(symbol: 'Rs. ', locale: 'en_IN', decimalDigits: 2).format(amount);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // --- HEADER ---
              pw.Center(child: pw.Text(shopName.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 24))),
              if (shopAddress.isNotEmpty) pw.Center(child: pw.Text(shopAddress, style: pw.TextStyle(font: font, fontSize: 12))),
              pw.SizedBox(height: 20),

              pw.Center(child: pw.Text("COMPREHENSIVE BUSINESS REPORT", style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.blue800))),
              pw.Center(child: pw.Text(fyRange, style: pw.TextStyle(font: font, fontSize: 14))),
              pw.SizedBox(height: 8),
              pw.Center(child: pw.Text("( 01-Apr-$startYear to 31-Mar-${startYear + 1} )", style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey700))),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 20),

              // --- 1. BUSINESS OVERVIEW ---
              pw.Text("1. BUSINESS KPI OVERVIEW", style: pw.TextStyle(font: fontBold, fontSize: 14)),
              pw.SizedBox(height: 10),
              pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
                  child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        // Left Column
                        pw.Expanded(
                            child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  _buildKpiRow("Total Revenue:", fmt(totalRevenue), font, fontBold, isBoldVal: true),
                                  pw.SizedBox(height: 8),
                                  _buildKpiRow("Net Profit:", fmt(netProfit), font, fontBold, valColor: netProfit >= 0 ? PdfColors.green700 : PdfColors.red700, isBoldVal: true),
                                  pw.SizedBox(height: 8),
                                  _buildKpiRow("Profit Margin:", "${profitMargin.toStringAsFixed(1)}%", font, fontBold),
                                ]
                            )
                        ),
                        pw.SizedBox(width: 20),
                        // Right Column
                        pw.Expanded(
                            child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  _buildKpiRow("Total Orders:", "$totalOrders", font, fontBold),
                                  pw.SizedBox(height: 8),
                                  _buildKpiRow("Avg Order Value:", fmt(aov), font, fontBold),
                                  pw.SizedBox(height: 8),
                                  _buildKpiRow("Total Discounts:", fmt(totalDiscount), font, fontBold, valColor: PdfColors.red700),
                                ]
                            )
                        )
                      ]
                  )
              ),
              pw.SizedBox(height: 25),

              // --- 2. CASH FLOW SUMMARY ---
              pw.Text("2. CASH FLOW SUMMARY", style: pw.TextStyle(font: fontBold, fontSize: 14)),
              pw.SizedBox(height: 10),
              pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
                  child: pw.Column(
                      children: [
                        _buildKpiRow("Total Money In (Sales Paid + Income):", fmt(moneyIn), font, fontBold, valColor: PdfColors.teal700),
                        pw.SizedBox(height: 6),
                        _buildKpiRow("Total Money Out (Expenses + Purchases):", fmt(moneyOut), font, fontBold, valColor: PdfColors.red700),
                        pw.Divider(color: PdfColors.grey300),
                        _buildKpiRow("Net Cash Flow:", fmt(netCashFlow), font, fontBold, isBoldVal: true, valColor: netCashFlow >= 0 ? PdfColors.blue800 : PdfColors.red800),
                      ]
                  )
              ),
              pw.SizedBox(height: 25),

              // --- 3. GST BREAKDOWN ---
              pw.Text("3. GST FILING BREAKDOWN", style: pw.TextStyle(font: fontBold, fontSize: 14)),
              pw.SizedBox(height: 10),

              if (gstSlabs.isEmpty)
                pw.Text("No tax data available for this financial year.", style: pw.TextStyle(font: font, fontSize: 12, fontStyle: pw.FontStyle.italic))
              else ...[
                pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey400),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1),
                      1: const pw.FlexColumnWidth(2),
                      2: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text("GST Slab", style: pw.TextStyle(font: fontBold, fontSize: 12))),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text("Taxable Sales Amount", textAlign: pw.TextAlign.right, style: pw.TextStyle(font: fontBold, fontSize: 12))),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text("Tax Collected", textAlign: pw.TextAlign.right, style: pw.TextStyle(font: fontBold, fontSize: 12))),
                          ]
                      ),
                      ...gstSlabs.map((s) => pw.TableRow(
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text("${(s['slab'] as num?)?.toInt() ?? 0}%", style: pw.TextStyle(font: font, fontSize: 12))),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(fmt((s['slab_sales'] as num?)?.toDouble() ?? 0.0), textAlign: pw.TextAlign.right, style: pw.TextStyle(font: font, fontSize: 12))),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(fmt((s['tax_amount'] as num?)?.toDouble() ?? 0.0), textAlign: pw.TextAlign.right, style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.red800))),
                          ]
                      )),
                      // Total Row
                      pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text("TOTAL", style: pw.TextStyle(font: fontBold, fontSize: 12))),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text("-", textAlign: pw.TextAlign.right, style: pw.TextStyle(font: fontBold, fontSize: 12))),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(fmt(totalGstAmount), textAlign: pw.TextAlign.right, style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.red800))),
                          ]
                      ),
                    ]
                ),
              ],

              pw.Spacer(),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text("Generated on: ${DateFormat('dd-MMM-yyyy hh:mm a').format(DateTime.now())}", style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600))
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: "FY_${startYear}_Comprehensive_Report");
  }

  // --- HELPER WIDGET FOR PDF KPI ROWS ---
  static pw.Widget _buildKpiRow(String label, String value, pw.Font font, pw.Font fontBold, {PdfColor? valColor, bool isBoldVal = false}) {
    return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey800)),
          pw.Text(value, style: pw.TextStyle(font: isBoldVal ? fontBold : font, fontSize: 12, color: valColor ?? PdfColors.black)),
        ]
    );
  }
}