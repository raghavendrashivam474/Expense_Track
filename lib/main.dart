import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.initialize();
  runApp(const ExpenseTrackerApp());
}

// ==================== DATABASE HELPER ====================
class DatabaseHelper {
  static Database? _database;
  static const String _dbName = 'expense_tracker.db';
  static const String _tableName = 'expenses';
  static const int _dbVersion = 1;

  // Initialize database
  static Future<void> initialize() async {
    try {
      final Directory documentsDirectory = await getApplicationDocumentsDirectory();
      final String path = p.join(documentsDirectory.path, _dbName);
      
      debugPrint('📁 Database path: $path');

      _database = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE $_tableName (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              amount REAL NOT NULL,
              date TEXT NOT NULL,
              category TEXT NOT NULL,
              createdAt TEXT NOT NULL
            )
          ''');
          debugPrint('✅ Database table created');
        },
        onOpen: (db) {
          debugPrint('✅ Database opened successfully');
        },
      );
    } catch (e) {
      debugPrint('❌ Database initialization error: $e');
    }
  }

  // Get database instance
  static Future<Database> get database async {
    if (_database == null) {
      await initialize();
    }
    return _database!;
  }

  // Insert expense
  static Future<bool> insertExpense(Map<String, dynamic> expense) async {
    try {
      final db = await database;
      await db.insert(
        _tableName,
        {
          'id': expense['id'],
          'title': expense['title'],
          'amount': expense['amount'],
          'date': (expense['date'] as DateTime).toIso8601String(),
          'category': expense['category'],
          'createdAt': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('✅ Expense inserted: ${expense['title']}');
      return true;
    } catch (e) {
      debugPrint('❌ Insert error: $e');
      return false;
    }
  }

  // Get all expenses
  static Future<List<Map<String, dynamic>>> getAllExpenses() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _tableName,
        orderBy: 'date DESC',
      );

      debugPrint('✅ Loaded ${maps.length} expenses from database');

      return maps.map((map) {
        return {
          'id': map['id'] as String,
          'title': map['title'] as String,
          'amount': (map['amount'] as num).toDouble(),
          'date': DateTime.parse(map['date'] as String),
          'category': map['category'] as String,
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ Load error: $e');
      return [];
    }
  }

  // Delete expense
  static Future<bool> deleteExpense(String id) async {
    try {
      final db = await database;
      await db.delete(
        _tableName,
        where: 'id = ?',
        whereArgs: [id],
      );
      debugPrint('✅ Expense deleted: $id');
      return true;
    } catch (e) {
      debugPrint('❌ Delete error: $e');
      return false;
    }
  }

  // Delete all expenses
  static Future<bool> deleteAllExpenses() async {
    try {
      final db = await database;
      await db.delete(_tableName);
      debugPrint('✅ All expenses deleted');
      return true;
    } catch (e) {
      debugPrint('❌ Delete all error: $e');
      return false;
    }
  }

  // Update expense
  static Future<bool> updateExpense(Map<String, dynamic> expense) async {
    try {
      final db = await database;
      await db.update(
        _tableName,
        {
          'title': expense['title'],
          'amount': expense['amount'],
          'date': (expense['date'] as DateTime).toIso8601String(),
          'category': expense['category'],
        },
        where: 'id = ?',
        whereArgs: [expense['id']],
      );
      debugPrint('✅ Expense updated: ${expense['title']}');
      return true;
    } catch (e) {
      debugPrint('❌ Update error: $e');
      return false;
    }
  }

  // Get total expenses
  static Future<double> getTotalExpenses() async {
    try {
      final db = await database;
      final result = await db.rawQuery('SELECT SUM(amount) as total FROM $_tableName');
      final total = result.first['total'];
      return total != null ? (total as num).toDouble() : 0.0;
    } catch (e) {
      debugPrint('❌ Total error: $e');
      return 0.0;
    }
  }

  // Get expenses by category
  static Future<Map<String, double>> getExpensesByCategory() async {
    try {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT category, SUM(amount) as total 
        FROM $_tableName 
        GROUP BY category
      ''');
      
      final Map<String, double> categoryTotals = {};
      for (var row in result) {
        categoryTotals[row['category'] as String] = (row['total'] as num).toDouble();
      }
      return categoryTotals;
    } catch (e) {
      debugPrint('❌ Category total error: $e');
      return {};
    }
  }
}

// ==================== MAIN APP ====================
class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ==================== HOME PAGE ====================
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _expenses = [];
  bool _isLoading = true;
  late AnimationController _fabController;

  static const Map<String, IconData> categoryIcons = {
    'Food': Icons.fastfood,
    'Transport': Icons.directions_car,
    'Shopping': Icons.shopping_bag,
    'Entertainment': Icons.movie,
    'Bills': Icons.receipt_long,
    'Health': Icons.local_hospital,
    'Education': Icons.school,
    'Other': Icons.category,
  };

  static const Map<String, Color> categoryColors = {
    'Food': Colors.orange,
    'Transport': Colors.blue,
    'Shopping': Colors.purple,
    'Entertainment': Colors.pink,
    'Bills': Colors.teal,
    'Health': Colors.red,
    'Education': Colors.indigo,
    'Other': Colors.grey,
  };

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _loadExpenses();
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  Future<void> _loadExpenses() async {
    setState(() => _isLoading = true);
    
    try {
      final expenses = await DatabaseHelper.getAllExpenses();
      if (mounted) {
        setState(() {
          _expenses = expenses;
          _isLoading = false;
        });
        _fabController.forward();
      }
    } catch (e) {
      debugPrint('Error loading expenses: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addExpense(Map<String, dynamic> expense) async {
    final success = await DatabaseHelper.insertExpense(expense);
    
    if (success) {
      await _loadExpenses();
      if (mounted) {
        _showSnackBar('Expense added successfully!', Colors.green);
      }
    } else {
      if (mounted) {
        _showSnackBar('Failed to add expense', Colors.red);
      }
    }
  }

  Future<void> _deleteExpense(String id, Map<String, dynamic> expense, int index) async {
    // Optimistic update
    setState(() {
      _expenses.removeWhere((e) => e['id'] == id);
    });

    final success = await DatabaseHelper.deleteExpense(id);

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${expense['title']} deleted'),
          backgroundColor: Colors.red[400],
          action: SnackBarAction(
            label: 'UNDO',
            textColor: Colors.white,
            onPressed: () async {
              await DatabaseHelper.insertExpense(expense);
              await _loadExpenses();
            },
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    if (!success) {
      await _loadExpenses();
    }
  }

  Future<void> _clearAllExpenses() async {
    final success = await DatabaseHelper.deleteAllExpenses();
    
    if (success) {
      setState(() {
        _expenses.clear();
      });
      if (mounted) {
        _showSnackBar('All expenses cleared', Colors.red);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  double get _totalAmount {
    return _expenses.fold(0.0, (sum, e) => sum + (e['amount'] as num).toDouble());
  }

  double get _monthlyTotal {
    final now = DateTime.now();
    return _expenses
        .where((e) {
          final date = e['date'] as DateTime;
          return date.month == now.month && date.year == now.year;
        })
        .fold(0.0, (sum, e) => sum + (e['amount'] as num).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.deepPurple),
                  SizedBox(height: 16),
                  Text('Loading your expenses...'),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadExpenses,
              color: Colors.deepPurple,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _buildSliverAppBar(),
                  _buildStatsSection(),
                  _buildListHeader(),
                  _expenses.isEmpty ? _buildEmptyState() : _buildExpenseList(),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
                ],
              ),
            ),
      floatingActionButton: ScaleTransition(
        scale: CurvedAnimation(parent: _fabController, curve: Curves.easeOutBack),
        child: FloatingActionButton.extended(
          onPressed: () => _showAddExpenseSheet(context),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          elevation: 4,
          icon: const Icon(Icons.add),
          label: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      stretch: true,
      backgroundColor: Colors.deepPurple,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: _loadExpenses,
        ),
        if (_expenses.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.white),
            onPressed: () => _showClearConfirmation(context),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        title: const Text(
          'Expense Tracker',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.deepPurple,
                Colors.purple,
                Colors.purpleAccent,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 50),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.white70,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₹${NumberFormat('#,##,###').format(_totalAmount.toInt())}',
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Total Expenses',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.receipt,
                title: 'Transactions',
                value: '${_expenses.length}',
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.calendar_month,
                title: 'This Month',
                value: '₹${NumberFormat.compact().format(_monthlyTotal)}',
                color: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListHeader() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'All Expenses',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_expenses.length} items',
                style: const TextStyle(
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long,
                size: 64,
                color: Colors.deepPurple.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No expenses yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to add your first expense',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showAddExpenseSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Add Expense'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final expense = _expenses[index];
          return _ExpenseCard(
            expense: expense,
            categoryIcon: categoryIcons[expense['category']] ?? Icons.category,
            categoryColor: categoryColors[expense['category']] ?? Colors.grey,
            onDelete: () => _deleteExpense(
              expense['id'] as String,
              expense,
              index,
            ),
            onTap: () => _showExpenseDetails(context, expense),
          );
        },
        childCount: _expenses.length,
      ),
    );
  }

  void _showAddExpenseSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddExpenseSheet(
        categoryIcons: categoryIcons,
        categoryColors: categoryColors,
        onSave: _addExpense,
      ),
    );
  }

  void _showExpenseDetails(BuildContext context, Map<String, dynamic> expense) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (categoryColors[expense['category']] ?? Colors.grey).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    categoryIcons[expense['category']] ?? Icons.category,
                    color: categoryColors[expense['category']] ?? Colors.grey,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expense['title'] as String,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        expense['category'] as String,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _DetailRow(
              icon: Icons.currency_rupee,
              label: 'Amount',
              value: '₹${NumberFormat('#,##,###.##').format(expense['amount'])}',
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.calendar_today,
              label: 'Date',
              value: DateFormat('EEEE, dd MMMM yyyy').format(expense['date'] as DateTime),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteExpense(expense['id'] as String, expense, 0);
                    },
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showClearConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Clear All?'),
          ],
        ),
        content: const Text(
          'This will permanently delete all your expenses. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearAllExpenses();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ==================== STAT CARD ====================
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== DETAIL ROW ====================
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey[600], size: 20),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.grey[600]),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ==================== EXPENSE CARD ====================
class _ExpenseCard extends StatelessWidget {
  final Map<String, dynamic> expense;
  final IconData categoryIcon;
  final Color categoryColor;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _ExpenseCard({
    required this.expense,
    required this.categoryIcon,
    required this.categoryColor,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = expense['date'] as DateTime;
    final amount = (expense['amount'] as num).toDouble();

    return Dismissible(
      key: Key(expense['id'] as String),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_forever, color: Colors.white, size: 28),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: categoryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(categoryIcon, color: categoryColor, size: 24),
            ),
            title: Text(
              expense['title'] as String,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Row(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: categoryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    expense['category'] as String,
                    style: TextStyle(
                      color: categoryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('dd MMM').format(date),
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            trailing: Text(
              '₹${NumberFormat('#,##,###').format(amount.toInt())}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.deepPurple,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== ADD EXPENSE SHEET ====================
class AddExpenseSheet extends StatefulWidget {
  final Map<String, IconData> categoryIcons;
  final Map<String, Color> categoryColors;
  final Function(Map<String, dynamic>) onSave;

  const AddExpenseSheet({
    super.key,
    required this.categoryIcons,
    required this.categoryColors,
    required this.onSave,
  });

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  String _selectedCategory = 'Food';
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Colors.deepPurple),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _saveExpense() async {
    final title = _titleController.text.trim();
    final amountText = _amountController.text.trim();

    if (title.isEmpty) {
      _showError('Please enter a title');
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      _showError('Please enter a valid amount');
      return;
    }

    setState(() => _isSaving = true);

    final expense = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': title,
      'amount': amount,
      'date': _selectedDate,
      'category': _selectedCategory,
    };

    await widget.onSave(expense);

    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPadding + 24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Header
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle, color: Colors.deepPurple, size: 28),
                    SizedBox(width: 8),
                    Text(
                      'New Expense',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Title field
                TextFormField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    hintText: 'What did you spend on?',
                    prefixIcon: const Icon(Icons.title),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),
                const SizedBox(height: 16),

                // Amount field
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount (₹)',
                    hintText: '0.00',
                    prefixIcon: const Icon(Icons.currency_rupee),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),
                const SizedBox(height: 16),

                // Category dropdown
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    prefixIcon: const Icon(Icons.category),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  items: widget.categoryIcons.keys.map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Row(
                        children: [
                          Icon(
                            widget.categoryIcons[category],
                            color: widget.categoryColors[category],
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(category),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedCategory = value);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Date picker
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: Colors.grey[700]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            DateFormat('EEEE, dd MMM yyyy').format(_selectedDate),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Save button
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveExpense,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save),
                              SizedBox(width: 8),
                              Text(
                                'Save Expense',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}