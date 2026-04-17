import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('bizmanager_v26.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    // 1. User Profile
    await db.execute('CREATE TABLE user_profile (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, shop_name TEXT, pin TEXT, phone TEXT, address TEXT)');

    // 2. Customers
    await db.execute('CREATE TABLE customers (phone TEXT PRIMARY KEY, name TEXT, address TEXT)');

    // 3. Categories
    await db.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, gst_rate REAL)');
    await db.insert('categories', {'name': 'Other', 'gst_rate': -1.0});
    await db.execute('CREATE TABLE suppliers (id INTEGER PRIMARY KEY AUTOINCREMENT, phone TEXT UNIQUE, name TEXT, address TEXT, balance_due REAL DEFAULT 0)');

    // 4. Products
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        name TEXT UNIQUE, 
        price REAL, 
        purchase_price REAL DEFAULT 0, 
        stock INTEGER, 
        gst_rate REAL, 
        low_stock_limit INTEGER DEFAULT 5,
        category_id INTEGER,
        FOREIGN KEY (category_id) REFERENCES categories (id)
      )
    ''');

    // 5. Invoices
    await db.execute('CREATE TABLE invoices (id INTEGER PRIMARY KEY AUTOINCREMENT, customer_name TEXT, customer_phone TEXT, date TEXT, total_amount REAL, discount REAL DEFAULT 0, paid_amount REAL, balance_due REAL)');

    // 6. Invoice Items
    await db.execute('''
      CREATE TABLE invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        invoice_id INTEGER, 
        product_id INTEGER, 
        product_name TEXT, 
        quantity INTEGER, 
        price REAL, 
        purchase_price REAL DEFAULT 0,
        gst_rate REAL, 
        line_total REAL
      )
    ''');

    // 7. Finance & History Tables
    await db.execute('CREATE TABLE payables (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, amount REAL, balance_due REAL, date TEXT)');
    await db.execute('CREATE TABLE settlements (id INTEGER PRIMARY KEY AUTOINCREMENT, txn_id INTEGER, txn_type TEXT, amount REAL, date TEXT)');
    await db.execute('CREATE TABLE expenses (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, amount REAL, date TEXT)');
    await db.execute('CREATE TABLE other_incomes (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, amount REAL, date TEXT)');
    await db.execute('CREATE TABLE purchases (id INTEGER PRIMARY KEY AUTOINCREMENT, product_name TEXT, supplier TEXT, quantity INTEGER, cost REAL, date TEXT)');
    await db.execute('CREATE TABLE other_receivables (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, amount REAL, balance_due REAL, date TEXT)');

  }
  // ====================================================
  //               INVOICE METHODS
  // ====================================================

  Future<int> createInvoice(Map<String, dynamic> invoice, List<Map<String, dynamic>> items) async {
    final db = await instance.database;
    return await db.transaction((txn) async {
      int id = await txn.insert('invoices', invoice);

      if (invoice['paid_amount'] > 0) {
        await txn.insert('settlements', {'txn_id': id, 'txn_type': 'receivable', 'amount': invoice['paid_amount'], 'date': invoice['date']});
      }

      for (var item in items) {
        final prodRes = await txn.query('products', columns: ['purchase_price'], where: 'id = ?', whereArgs: [item['product_id']]);
        double cost = 0.0;
        if (prodRes.isNotEmpty) cost = prodRes.first['purchase_price'] as double? ?? 0.0;

        await txn.insert('invoice_items', {
          'invoice_id': id,
          'product_id': item['product_id'],
          'product_name': item['product_name'],
          'quantity': item['quantity'],
          'price': item['price'],
          'purchase_price': cost,
          'gst_rate': item['gst_rate'],
          'line_total': item['line_total']
        });
        await txn.rawUpdate('UPDATE products SET stock = stock - ? WHERE name = ?', [item['quantity'], item['product_name']]);
      }
      return id;
    });
  }

  Future<void> updateInvoice(int id, Map<String, dynamic> invoice, List<Map<String, dynamic>> items) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final oldItems = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);
      for (var item in oldItems) {
        await txn.rawUpdate('UPDATE products SET stock = stock + ? WHERE name = ?', [item['quantity'], item['product_name']]);
      }

      await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);
      await txn.delete('settlements', where: 'txn_id = ? AND txn_type = ?', whereArgs: [id, 'receivable']);

      await txn.update('invoices', invoice, where: 'id = ?', whereArgs: [id]);

      for (var item in items) {
        final prodRes = await txn.query('products', columns: ['purchase_price'], where: 'id = ?', whereArgs: [item['product_id']]);
        double cost = 0.0;
        if (prodRes.isNotEmpty) cost = prodRes.first['purchase_price'] as double? ?? 0.0;

        await txn.insert('invoice_items', {
          'invoice_id': id,
          'product_id': item['product_id'],
          'product_name': item['product_name'],
          'quantity': item['quantity'],
          'price': item['price'],
          'purchase_price': cost,
          'gst_rate': item['gst_rate'],
          'line_total': item['line_total']
        });
        await txn.rawUpdate('UPDATE products SET stock = stock - ? WHERE name = ?', [item['quantity'], item['product_name']]);
      }

      if (invoice['paid_amount'] > 0) {
        await txn.insert('settlements', {'txn_id': id, 'txn_type': 'receivable', 'amount': invoice['paid_amount'], 'date': invoice['date']});
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAllInvoices({String query = ''}) async {
    final db = await instance.database;
    String sql = 'SELECT * FROM invoices WHERE 1=1';
    if (query.isNotEmpty) sql += " AND (customer_name LIKE '%$query%' OR id LIKE '%$query%')";
    sql += ' ORDER BY date DESC';
    return await db.rawQuery(sql);
  }

  Future<List<Map<String, dynamic>>> getInvoiceItems(int invoiceId) async => await (await instance.database).query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);

  Future<void> deleteInvoice(int id) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final items = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);
      for (var item in items) {
        await txn.rawUpdate('UPDATE products SET stock = stock + ? WHERE name = ?', [item['quantity'], item['product_name']]);
      }
      await txn.delete('invoices', where: 'id = ?', whereArgs: [id]);
      await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [id]);
      await txn.delete('settlements', where: 'txn_id = ? AND txn_type = ?', whereArgs: [id, 'receivable']);
    });
  }

  Future<void> settleInvoice(int id, double amountPaid) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.rawUpdate('UPDATE invoices SET paid_amount = paid_amount + ?, balance_due = balance_due - ? WHERE id = ?', [amountPaid, amountPaid, id]);
      await txn.insert('settlements', {'txn_id': id, 'txn_type': 'receivable', 'amount': amountPaid, 'date': DateTime.now().toString()});
    });
  }

  // ====================================================
  //               PRODUCT & INVENTORY METHODS
  // ====================================================

  Future<List<Map<String, dynamic>>> getProductsWithCategory() async {
    final db = await instance.database;
    return await db.rawQuery('SELECT p.*, c.name as category_name FROM products p LEFT JOIN categories c ON p.category_id = c.id ORDER BY c.name, p.name');
  }

  Future<int> addProduct(Map<String, dynamic> row) async => await (await instance.database).insert('products', row);
  Future<int> updateProduct(Map<String, dynamic> row) async => await (await instance.database).update('products', row, where: 'id = ?', whereArgs: [row['id']]);
  Future<int> deleteProduct(int id) async => await (await instance.database).delete('products', where: 'id = ?', whereArgs: [id]);

  Future<bool> checkProductNameExists(String name, {int? excludeId}) async {
    final db = await instance.database;
    String sql = "SELECT COUNT(*) FROM products WHERE name = '$name'";
    if (excludeId != null) sql += " AND id != $excludeId";
    final res = await db.rawQuery(sql);
    return Sqflite.firstIntValue(res)! > 0;
  }

  Future<List<Map<String, dynamic>>> getProducts() async => await (await instance.database).query('products');

  Future<void> addStock(String productName, int qty, double cost, double paidAmount, String supplier) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      String dateStr = DateTime.now().toString();

      await txn.insert('purchases', {
        'product_name': productName,
        'supplier': supplier,
        'quantity': qty,
        'cost': cost,
        'date': dateStr
      });

      await txn.rawUpdate('UPDATE products SET stock = stock + ? WHERE name = ?', [qty, productName]);

      double balanceDue = cost - paidAmount;
      if (balanceDue > 0) {
        int payableId = await txn.insert('payables', {
          'title': '$supplier ($productName)',
          'amount': cost,
          'balance_due': balanceDue,
          'date': dateStr
        });

        if (paidAmount > 0) {
          await txn.insert('settlements', {
            'txn_id': payableId,
            'txn_type': 'payable',
            'amount': paidAmount,
            'date': dateStr
          });
        }
      }
    });
  }

  Future<void> removeStock(String productName, int qty, String reason) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.insert('purchases', {'product_name': productName, 'supplier': "Adj: $reason", 'quantity': -qty, 'cost': 0, 'date': DateTime.now().toString()});
      await txn.rawUpdate('UPDATE products SET stock = stock - ? WHERE name = ?', [qty, productName]);
    });
  }

  Future<List<Map<String, dynamic>>> getProductHistory(String productName) async {
    final db = await instance.database;
    final sales = await db.rawQuery("SELECT i.date, 'SALE' as type, ('Inv #' || i.id) as ref, ii.quantity, ii.line_total as amount FROM invoice_items ii JOIN invoices i ON ii.invoice_id = i.id WHERE ii.product_name = ?", [productName]);
    final purchases = await db.rawQuery("SELECT date, 'PURCHASE' as type, supplier as ref, quantity, cost as amount FROM purchases WHERE product_name = ?", [productName]);
    List<Map<String, dynamic>> combined = [...sales, ...purchases];
    combined.sort((a, b) => b['date'].compareTo(a['date']));
    return combined;
  }

  Future<int> addCategory(String name, double gstRate) async => await (await instance.database).insert('categories', {'name': name, 'gst_rate': gstRate});

  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT c.*, COUNT(p.id) as product_count 
      FROM categories c 
      LEFT JOIN products p ON c.id = p.category_id 
      GROUP BY c.id
      ORDER BY c.name
    ''');
  }

  Future<int> updateCategory(int id, String name, double gstRate) async => await (await instance.database).update('categories', {'name': name, 'gst_rate': gstRate}, where: 'id = ?', whereArgs: [id]);
  Future<int> deleteCategory(int id) async => await (await instance.database).delete('categories', where: 'id = ?', whereArgs: [id]);

  // ====================================================
  //               FINANCE & STATS METHODS
  // ====================================================

  Future<Map<String, double>> getStats() async {
    final db = await database;

    // Gets the current month in 'YYYY-MM' format (e.g., '2026-02')
    String currentMonth = DateFormat('yyyy-MM').format(DateTime.now());

    // 1. Current Month Sales
    var salesRes = await db.rawQuery('''
      SELECT SUM(total_amount) as total 
      FROM invoices 
      WHERE date LIKE '$currentMonth%'
    ''');
    double currentMonthSales = (salesRes.first['total'] as num?)?.toDouble() ?? 0.0;

    // 2. Current Month COGS (Cost of Goods Sold)
    var cogsRes = await db.rawQuery('''
      SELECT SUM(ii.quantity * ii.purchase_price) as cogs 
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE i.date LIKE '$currentMonth%'
    ''');
    double currentMonthCogs = (cogsRes.first['cogs'] as num?)?.toDouble() ?? 0.0;

    // Gross Profit = Sales - COGS
    double currentMonthGrossProfit = currentMonthSales - currentMonthCogs;

    // 3. Current Month Expenses
    var expRes = await db.rawQuery('''
      SELECT SUM(amount) as total 
      FROM expenses 
      WHERE date LIKE '$currentMonth%'
    ''');
    double currentMonthExpenses = (expRes.first['total'] as num?)?.toDouble() ?? 0.0;

    // 4. Current Month Other Income
    var incRes = await db.rawQuery('''
      SELECT SUM(amount) as total 
      FROM other_incomes 
      WHERE date LIKE '$currentMonth%'
    ''');
    double currentMonthOtherIncome = (incRes.first['total'] as num?)?.toDouble() ?? 0.0;

    // NET PROFIT MATH
    double currentMonthNetProfit = currentMonthGrossProfit - currentMonthExpenses + currentMonthOtherIncome;

    // 5. Total Receivables & Payables (Kept as lifetime totals)
    var recRes = await db.rawQuery('SELECT SUM(balance_due) as total FROM invoices WHERE balance_due > 0');
    double receivables = (recRes.first['total'] as num?)?.toDouble() ?? 0.0;

    var payRes = await db.rawQuery('SELECT SUM(balance_due) as total FROM payables WHERE balance_due > 0');
    double payables = (payRes.first['total'] as num?)?.toDouble() ?? 0.0;

    return {
      'current_month_sales': currentMonthSales,
      'current_month_net_profit': currentMonthNetProfit,
      'receivables': receivables,
      'payables': payables,
    };
  }

  Future<List<Map<String, dynamic>>> getSalesReports(String type) async {
    final db = await instance.database;
    String dateFormat;
    if (type == 'Daily') dateFormat = '%Y-%m-%d';
    else if (type == 'Weekly') dateFormat = '%Y-%W';
    else if (type == 'Monthly') dateFormat = '%Y-%m';
    else dateFormat = '%Y';
    return await db.rawQuery("SELECT strftime('$dateFormat', date) as period, MIN(date) as raw_date, SUM(total_amount) as total FROM invoices GROUP BY period ORDER BY period DESC");
  }

  Future<List<Map<String, dynamic>>> getSalesReceivables({String query = ''}) async {
    final db = await instance.database;
    String sql = 'SELECT * FROM invoices WHERE balance_due > 0';
    if (query.isNotEmpty) sql += " AND (customer_name LIKE '%$query%' OR customer_phone LIKE '%$query%')";
    sql += ' ORDER BY date DESC';
    return await db.rawQuery(sql);
  }

  Future<int> addOtherReceivable(Map<String, dynamic> row) async => await (await instance.database).insert('other_receivables', row);

  Future<List<Map<String, dynamic>>> getOtherReceivables({String query = ''}) async {
    final db = await instance.database;
    String sql = 'SELECT * FROM other_receivables WHERE balance_due > 0';
    if (query.isNotEmpty) sql += " AND title LIKE '%$query%'";
    sql += ' ORDER BY date DESC';
    return await db.rawQuery(sql);
  }

  Future<void> updateOtherReceivable(int id, String title, double newAmount) async {
    final db = await instance.database;
    final res = await db.query('other_receivables', where: 'id = ?', whereArgs: [id]);
    if (res.isEmpty) return;
    final oldRow = res.first;
    double paid = (oldRow['amount'] as double) - (oldRow['balance_due'] as double);
    double newBalance = newAmount - paid;
    await db.update('other_receivables', {'title': title, 'amount': newAmount, 'balance_due': newBalance}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteOtherReceivable(int id) async {
    final db = await instance.database;
    await db.delete('other_receivables', where: 'id = ?', whereArgs: [id]);
    await db.delete('settlements', where: 'txn_id = ? AND txn_type = ?', whereArgs: [id, 'other_receivable']);
  }

  Future<void> settleOtherReceivable(int id, double amountPaid) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.rawUpdate('UPDATE other_receivables SET balance_due = balance_due - ? WHERE id = ?', [amountPaid, id]);
      await txn.insert('settlements', {'txn_id': id, 'txn_type': 'other_receivable', 'amount': amountPaid, 'date': DateTime.now().toString()});
    });
  }

  Future<List<Map<String, dynamic>>> getPayables({String query = ''}) async {
    final db = await instance.database;
    String sql = 'SELECT * FROM payables WHERE balance_due > 0';
    if (query.isNotEmpty) sql += " AND title LIKE '%$query%'";
    sql += ' ORDER BY date DESC';
    return await db.rawQuery(sql);
  }

  Future<int> addPayable(Map<String, dynamic> row) async => await (await instance.database).insert('payables', row);

  Future<void> updatePayable(int id, String title, double newAmount) async {
    final db = await instance.database;
    final res = await db.query('payables', where: 'id = ?', whereArgs: [id]);
    if (res.isEmpty) return;
    final oldRow = res.first;
    double oldAmount = oldRow['amount'] as double;
    double oldBalance = oldRow['balance_due'] as double;
    double paid = oldAmount - oldBalance;
    double newBalance = newAmount - paid;
    await db.update('payables', {'title': title, 'amount': newAmount, 'balance_due': newBalance}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePayable(int id) async {
    final db = await instance.database;
    await db.delete('payables', where: 'id = ?', whereArgs: [id]);
    await db.delete('settlements', where: 'txn_id = ? AND txn_type = ?', whereArgs: [id, 'payable']);
  }

  Future<void> settlePayable(int id, double amountPaid) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.rawUpdate('UPDATE payables SET balance_due = balance_due - ? WHERE id = ?', [amountPaid, id]);
      await txn.insert('settlements', {'txn_id': id, 'txn_type': 'payable', 'amount': amountPaid, 'date': DateTime.now().toString()});
    });
  }

  Future<void> updateReceivableBasic(int id, String name, double newAmount) async {
    final db = await instance.database;
    final res = await db.query('invoices', where: 'id = ?', whereArgs: [id]);
    if (res.isEmpty) return;
    final oldRow = res.first;
    double paid = oldRow['paid_amount'] as double;
    double newBalance = newAmount - paid;
    await db.update('invoices', {'customer_name': name, 'total_amount': newAmount, 'balance_due': newBalance}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getSettlementHistory(int txnId, String type) async {
    return await (await instance.database).query('settlements', where: 'txn_id = ? AND txn_type = ?', whereArgs: [txnId, type], orderBy: 'date ASC');
  }

  Future<int> addExpense(Map<String, dynamic> row) async => await (await instance.database).insert('expenses', row);
  Future<List<Map<String, dynamic>>> getExpenses() async => await (await instance.database).query('expenses', orderBy: 'date DESC');
  Future<int> updateExpense(Map<String, dynamic> row) async => await (await instance.database).update('expenses', row, where: 'id = ?', whereArgs: [row['id']]);
  Future<int> deleteExpense(int id) async => await (await instance.database).delete('expenses', where: 'id = ?', whereArgs: [id]);

  Future<int> addIncome(Map<String, dynamic> row) async => await (await instance.database).insert('other_incomes', row);
  Future<List<Map<String, dynamic>>> getIncomes() async => await (await instance.database).query('other_incomes', orderBy: 'date DESC');
  Future<int> updateIncome(Map<String, dynamic> row) async => await (await instance.database).update('other_incomes', row, where: 'id = ?', whereArgs: [row['id']]);
  Future<int> deleteIncome(int id) async => await (await instance.database).delete('other_incomes', where: 'id = ?', whereArgs: [id]);

  // ====================================================
  //               USER & CUSTOMER METHODS
  // ====================================================

  Future<bool> isUserRegistered() async { final db = await instance.database; final res = await db.rawQuery('SELECT COUNT(*) FROM user_profile'); return Sqflite.firstIntValue(res)! > 0; }
  Future<void> registerUser(String name, String shopName, String pin, String phone, String address) async { final db = await instance.database; await db.insert('user_profile', {'name': name, 'shop_name': shopName, 'pin': pin, 'phone': phone, 'address': address}); }
  Future<Map<String, dynamic>?> getUser() async { final db = await instance.database; final res = await db.query('user_profile', limit: 1); return res.isNotEmpty ? res.first : null; }
  Future<void> updateUserProfile(String name, String shopName, String phone, String address) async { final db = await instance.database; await db.update('user_profile', {'name': name, 'shop_name': shopName, 'phone': phone, 'address': address}, where: 'id = ?', whereArgs: [1]); }

  Future<int> addCustomer(Map<String, dynamic> row) async => await (await instance.database).insert('customers', row, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<List<Map<String, dynamic>>> getCustomers() async => await (await instance.database).query('customers');
  Future<List<Map<String, dynamic>>> getCustomerInvoices(String phone) async => await (await instance.database).query('invoices', where: 'customer_phone = ?', whereArgs: [phone], orderBy: 'date DESC');
  Future<int> updateCustomer(Map<String, dynamic> row) async { final db = await instance.database; return await db.update('customers', row, where: 'phone = ?', whereArgs: [row['phone']]); }
  Future<int> deleteCustomer(String phone) async { final db = await instance.database; return await db.delete('customers', where: 'phone = ?', whereArgs: [phone]); }

  Future<int> addSupplier(Map<String, dynamic> row) async => await (await instance.database).insert('suppliers', row, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<List<Map<String, dynamic>>> getSuppliers() async => await (await instance.database).query('suppliers', orderBy: 'name ASC');
  Future<int> updateSupplier(Map<String, dynamic> row) async { final db = await instance.database; return await db.update('suppliers', row, where: 'id = ?', whereArgs: [row['id']]); }
  Future<int> deleteSupplier(int id) async { final db = await instance.database; return await db.delete('suppliers', where: 'id = ?', whereArgs: [id]); }

  Future<List<Map<String, dynamic>>> getSupplierPurchases(String supplierName) async {
    final db = await instance.database;
    return await db.query('purchases', where: 'supplier = ?', whereArgs: [supplierName], orderBy: 'date DESC');
  }

  // ====================================================
  //               ADVANCED REPORTING
  // ====================================================

  Future<Map<String, dynamic>> getAdvancedReportData(int year, int month) async {
    final db = await instance.database;

    String dateFilter;
    String iDateFilter;
    String trendGroupFormat;

    // If month is 0, we fetch the whole year. Otherwise, fetch the specific month.
    if (month == 0) {
      // Fetch data for Financial Year: April 1st to March 31st
      String nextYear = (year + 1).toString();
      dateFilter = "date >= '$year-04-01 00:00:00' AND date <= '$nextYear-03-31 23:59:59'";
      iDateFilter = "i.date >= '$year-04-01 00:00:00' AND i.date <= '$nextYear-03-31 23:59:59'";
      trendGroupFormat = "%Y-%m"; // Group chart by month for yearly view
    } else {
      String monthStr = month.toString().padLeft(2, '0');
      dateFilter = "strftime('%Y-%m', date) = '$year-$monthStr'";
      iDateFilter = "strftime('%Y-%m', i.date) = '$year-$monthStr'";
      trendGroupFormat = "%Y-%m-%d"; // Group chart by day for monthly view
    }

    String thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);

    // 1. MONTHLY / YEARLY KPIs
    final monthlyKpis = await db.rawQuery('''
      SELECT 
        COUNT(id) as total_orders,
        IFNULL(SUM(total_amount), 0) as total_revenue,
        IFNULL(SUM(paid_amount), 0) as total_paid,
        IFNULL(SUM(balance_due), 0) as total_due,
        IFNULL(SUM(discount), 0) as total_discount
      FROM invoices 
      WHERE $dateFilter
    ''');

    final monthlyProfit = await db.rawQuery('''
      SELECT IFNULL(SUM((ii.price - IFNULL(ii.purchase_price, 0)) * ii.quantity), 0) as total_profit,
             IFNULL(SUM(ii.price * ii.quantity * (IFNULL(ii.gst_rate, 0) / 100.0)), 0) as total_gst
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE $iDateFilter
    ''');

    // Slab-wise GST Breakdown
    final gstSlabs = await db.rawQuery('''
      SELECT 
        IFNULL(ii.gst_rate, 0) as slab,
        IFNULL(SUM(ii.line_total), 0) as total_sales,
        IFNULL(SUM(ii.price * ii.quantity * (IFNULL(ii.gst_rate, 0) / 100.0)), 0) as tax_collected
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE $iDateFilter
      GROUP BY slab
      ORDER BY slab ASC
    ''');

    // 2. TOP CUSTOMERS
    final topCustomers = await db.rawQuery('''
      SELECT customer_name, SUM(total_amount) as spent, COUNT(id) as orders
      FROM invoices
      WHERE $dateFilter AND customer_name != 'Walk-in Customer'
      GROUP BY customer_name
      ORDER BY spent DESC
      LIMIT 5
    ''');

    // 3. Category Profits
    final catStats = await db.rawQuery('''
      SELECT c.id, c.name as category,
             (SELECT COUNT(id) FROM products WHERE category_id = c.id) as product_count,
             (SELECT IFNULL(AVG(price), 0) FROM products WHERE category_id = c.id) as avg_sale_price,
             (SELECT IFNULL(AVG(purchase_price), 0) FROM products WHERE category_id = c.id) as avg_buy_price,
             IFNULL(SUM(s.quantity), 0) as total_qty_sold,
             IFNULL(SUM(s.line_total), 0) as sales,
             IFNULL(SUM((s.price - IFNULL(s.purchase_price, 0)) * s.quantity), 0) as profit,
             IFNULL(SUM(s.price * s.quantity * (IFNULL(s.gst_rate, 0) / 100.0)), 0) as gst_collected
      FROM categories c
      LEFT JOIN products p ON p.category_id = c.id
      LEFT JOIN (
           SELECT ii.product_id, ii.quantity, ii.line_total, ii.price, ii.purchase_price, ii.gst_rate
           FROM invoice_items ii
           JOIN invoices i ON ii.invoice_id = i.id
           WHERE $iDateFilter
      ) s ON s.product_id = p.id
      GROUP BY c.id
      ORDER BY sales DESC, profit DESC
    ''');

    // 4. Most Selling
    final prodStats = await db.rawQuery('''
      SELECT ii.product_name,
             SUM(ii.quantity) as qty,
             SUM((ii.price - IFNULL(ii.purchase_price, 0)) * ii.quantity) as profit
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE $iDateFilter
      GROUP BY ii.product_name
    ''');

    Map<String, dynamic>? mostSelling;
    Map<String, dynamic>? mostProfitable;
    if (prodStats.isNotEmpty) {
      var sortedByQty = List<Map<String, dynamic>>.from(prodStats)..sort((a, b) => (b['qty'] as num).compareTo(a['qty'] as num));
      mostSelling = sortedByQty.first;
      var sortedByProfit = List<Map<String, dynamic>>.from(prodStats)..sort((a, b) => (b['profit'] as num).compareTo(a['profit'] as num));
      mostProfitable = sortedByProfit.first;
    }

    // 5. Trend
    final trendStats = await db.rawQuery('''
      SELECT strftime('$trendGroupFormat', i.date) as date_str,
             SUM(ii.line_total) as sales,
             SUM((ii.price - IFNULL(ii.purchase_price, 0)) * ii.quantity) as profit
      FROM invoices i
      JOIN invoice_items ii ON i.id = ii.invoice_id
      WHERE $iDateFilter
      GROUP BY date_str
      ORDER BY date_str ASC
    ''');

    // 6. Inventory Valuation
    final invVal = await db.rawQuery('''
      SELECT SUM(stock * purchase_price) as capital, SUM(stock * price) as revenue FROM products WHERE stock > 0
    ''');

    // 7. Dead Stock
    final deadStock = await db.rawQuery('''
      SELECT p.name, p.stock 
      FROM products p
      WHERE p.stock > 0 AND p.id NOT IN (
        SELECT DISTINCT ii.product_id 
        FROM invoice_items ii 
        JOIN invoices i ON ii.invoice_id = i.id 
        WHERE i.date >= '$thirtyDaysAgo'
      )
    ''');

    // 8. Expenses & Cash Flow
    final expenses = await db.rawQuery('''
      SELECT title, SUM(amount) as total
      FROM expenses
      WHERE $dateFilter
      GROUP BY title
    ''');

    // Add query for grouping other incomes (ADDED HERE)
    final otherIncomesList = await db.rawQuery('''
      SELECT title, SUM(amount) as total
      FROM other_incomes
      WHERE $dateFilter
      GROUP BY title
      ORDER BY total DESC
    ''');

    final income = await db.rawQuery("SELECT SUM(amount) as t FROM other_incomes WHERE $dateFilter");
    final expenseTotal = await db.rawQuery("SELECT SUM(amount) as t FROM expenses WHERE $dateFilter");
    final purchasesTotal = await db.rawQuery("SELECT SUM(cost) as t FROM purchases WHERE $dateFilter");

    double moneyIn = (monthlyKpis.isNotEmpty ? (monthlyKpis.first['total_paid'] as num? ?? 0).toDouble() : 0.0) + (income.first['t'] as num? ?? 0).toDouble();
    double moneyOut = (expenseTotal.first['t'] as num? ?? 0).toDouble() + (purchasesTotal.first['t'] as num? ?? 0).toDouble();

    return {
      'monthly_kpis': monthlyKpis.isNotEmpty ? monthlyKpis.first : null,
      'monthly_profit_tax': monthlyProfit.isNotEmpty ? monthlyProfit.first : null,
      'gst_slabs': gstSlabs,
      'top_customers': topCustomers,
      'category_stats': catStats,
      'most_selling': mostSelling,
      'most_profitable': mostProfitable,
      'trend_stats': trendStats,
      'inv_value': invVal.isNotEmpty ? invVal.first : null,
      'dead_stock': deadStock,
      'expenses': expenses,
      'other_incomes_list': otherIncomesList, // Added mapping here
      'cash_flow': {'in': moneyIn, 'out': moneyOut},
    };
  }
}
