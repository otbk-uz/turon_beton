import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:turon_beton/colors/colors.dart';
import 'package:turon_beton/config.dart';
import 'package:turon_beton/config/database/database.dart';
import 'package:turon_beton/config/translate/translate.dart';
import 'package:turon_beton/models/models.dart';
import 'package:turon_beton/pages/splash.dart';

// ==========================================
// 4. STATE MANAGEMENT
// ==========================================
class AppState extends ChangeNotifier {
  static String currentLang = 'uz_lat';
  static ThemeMode currentTheme = ThemeMode.light;

  String _lang = 'uz_lat';
  ThemeMode _theme = ThemeMode.light;
  UserModel? _currentUser;

  String get lang => _lang;
  ThemeMode get theme => _theme;
  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  void setLang(String value) {
    _lang = value;
    currentLang = value;
    notifyListeners();
  }

  void setTheme(ThemeMode value) {
    _theme = value;
    currentTheme = value;
    notifyListeners();
  }

  void setUser(UserModel user) {
    _currentUser = user;
    notifyListeners();
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }
}

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);
  int get count => _items.length;
  bool get isEmpty => _items.isEmpty;

  double get totalSum => _items.fold(0, (sum, item) => sum + item.totalPrice);

  void addItem(CartItem item) {
    _items.add(item);
    notifyListeners();
  }

  void removeItem(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      notifyListeners();
    }
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}

// ==========================================
// 5. XIZMATLAR
// ==========================================
class FirebaseService {
  static Future<String?> sendOrder(OrderModel order) async {
    try {
      if (!AppConfig.isConfigured) return null;
      final response = await http.post(
        Uri.parse(AppConfig.firebaseUrl),
        body: json.encode(order.toFirebaseJson()),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['name'];
      }
      return null;
    } catch (e) {
      debugPrint('Firebase xatolik: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchOrders(
      String userPhone) async {
    try {
      if (!AppConfig.isConfigured) return [];
      final response = await http.get(Uri.parse(AppConfig.firebaseUrl));
      if (response.statusCode == 200 && response.body != "null") {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<Map<String, dynamic>> orders = [];
        data.forEach((key, value) {
          if (value['userPhone'] == userPhone) {
            orders.add({
              'id': key,
              'date': value['date'] ?? 'Sana yo\'q',
              'items': value['itemsText'] ?? '',
              'total': value['totalAmount'] ?? '0',
              'status': value['status'] ?? 'KUTILMOQDA...',
            });
          }
        });
        orders.sort((a, b) => b['date'].compareTo(a['date']));
        return orders;
      }
      return [];
    } catch (e) {
      debugPrint('Fetch xatolik: $e');
      return [];
    }
  }
}

class TelegramService {
  static Future<bool> sendOrderNotification(
      OrderModel order, String orderId) async {
    try {
      if (!AppConfig.isConfigured) return false;
      final itemsText = order.items
          .map((e) => "${e.qty}x ${e.name} (${e.details})")
          .join("\n");
      final message = "🚨 *YANGI BUYURTMA KELDI!* 🚨\n\n"
          "👤 *Mijoz:* ${order.userName}\n"
          "📞 *Tel:* +998 ${order.userPhone}\n"
          "📍 *Manzil:* ${order.userAddress}\n\n"
          "🛒 *BUYURTMALAR:*\n$itemsText\n\n"
          "💰 *JAMI SUMMA:* ${order.totalAmount.toStringAsFixed(0)} so'm";

      final url =
          "https://api.telegram.org/bot${AppConfig.botToken}/sendMessage";
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "chat_id": AppConfig.chatId,
          "text": message,
          "parse_mode": "Markdown",
          "reply_markup": {
            "inline_keyboard": [
              [
                {"text": "✅ QABUL QILINDI", "callback_data": "process_$orderId"}
              ],
              [
                {
                  "text": "🚀 TAYYOR (YETKAZISH)",
                  "callback_data": "delivery_$orderId"
                }
              ]
            ]
          }
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Telegram xatolik: $e');
      return false;
    }
  }

  static Future<bool> sendExcelDocument(
      List<int> excelBytes, String fileName, int? replyToMessageId) async {
    try {
      if (!AppConfig.isConfigured) return false;
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
            'https://api.telegram.org/bot${AppConfig.botToken}/sendDocument'),
      );
      request.fields['chat_id'] = AppConfig.chatId;
      if (replyToMessageId != null) {
        request.fields['reply_to_message_id'] = replyToMessageId.toString();
      }
      request.files.add(
        http.MultipartFile.fromBytes('document', excelBytes,
            filename: fileName),
      );
      final response = await request.send();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Excel yuborish xatolik: $e');
      return false;
    }
  }
}

class ExcelService {
  static List<int> generateOrderExcel({
    required String userName,
    required String userPhone,
    required String userAddress,
    required List<CartItem> items,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];

    final titleCell = sheet.cell(CellIndex.indexByString("A1"));
    titleCell.value = TextCellValue("TURON BETON");
    titleCell.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString("#1E3A5F"),
      fontColorHex: ExcelColor.fromHexString("#FFFFFF"),
      bold: true,
    );
    sheet.merge(CellIndex.indexByString("A1"), CellIndex.indexByString("F1"));

    sheet.cell(CellIndex.indexByString("A3")).value =
        TextCellValue("Мижоз: $userName");
    sheet.cell(CellIndex.indexByString("A4")).value = TextCellValue(
        "Манзил: ${userAddress.isEmpty ? 'Киритилмаган' : userAddress}");
    sheet.cell(CellIndex.indexByString("A5")).value =
        TextCellValue("Тел: +998 $userPhone");

    final headers = [
      'Тури',
      'Нагрузка',
      'Улчами',
      'Эни',
      'Сони',
      'Метри',
      'Нархи',
      'Суммаси'
    ];
    for (int i = 0; i < headers.length; i++) {
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 7));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString("#00BFA5"),
        fontColorHex: ExcelColor.fromHexString("#FFFFFF"),
        bold: true,
      );
    }

    int rowIdx = 8;
    double jamiSumma = 0;
    int totalQty = 0;

    for (var item in items) {
      totalQty += item.qty;
      final itemSumma = item.totalPrice - item.dostavka;
      jamiSumma += itemSumma;

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx))
          .value = TextCellValue(item.name);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx))
          .value = TextCellValue(item.details.replaceAll('\n', ' '));
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx))
          .value = IntCellValue(item.qty);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx))
          .value = TextCellValue(item.meters ?? '-');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx))
          .value = DoubleCellValue(item.price);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIdx))
          .value = DoubleCellValue(itemSumma);
      rowIdx++;
    }

    final totalLabelCell = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx));
    totalLabelCell.value = TextCellValue("ЖАМИ:");
    totalLabelCell.cellStyle = CellStyle(bold: true);
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx))
        .value = IntCellValue(totalQty);
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIdx))
        .value = DoubleCellValue(jamiSumma);

    sheet.setColumnWidth(0, 20);
    sheet.setColumnWidth(2, 30);

    return excel.encode()!;
  }
}

// ==========================================
// 7. ASOSIY DASTUR (Modern Theme)
// ==========================================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: const TuronBetonApp(),
    ),
  );
}

class TuronBetonApp extends StatelessWidget {
  const TuronBetonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Turon Beton',
          themeMode: appState.theme,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              secondary: AppColors.accent,
              surface: AppColors.surface,
              background: AppColors.background,
              error: Color(0xFFE22825),
              onPrimary: Colors.white,
              onSecondary: Colors.white,
              onSurface: AppColors.textPrimary,
              onBackground: AppColors.textPrimary,
            ),
            scaffoldBackgroundColor: AppColors.background,
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.accent, width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              secondary: AppColors.accent,
              surface: Color(0xFF1E293B),
              background: Color(0xFF0F172A),
              onPrimary: Colors.white,
              onSurface: Colors.white,
            ),
            scaffoldBackgroundColor: const Color(0xFF0F172A),
          ),
          home: const SplashScreenAnimated(),
        );
      },
    );
  }
}

// ==========================================
// 9. ZAMONAVIY AUTH EKRAN (Glassmorphism)
// ==========================================
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  bool isPasswordHidden = true;
  String selectedRoleKey = 'role_client';
  String selectedMasterTypeKey = 'm_santexnik';

  final phoneCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final confirmPassCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    phoneCtrl.dispose();
    passCtrl.dispose();
    confirmPassCtrl.dispose();
    nameCtrl.dispose();
    addressCtrl.dispose();
    super.dispose();
  }

  void _loginOrRegister() {
    if (!formKey.currentState!.validate()) return;

    UserRole role = UserRole.client;
    if (isLogin && phoneCtrl.text == '991234567' && passCtrl.text == 'admin') {
      role = UserRole.admin;
    } else if (selectedRoleKey == 'role_master') {
      role = UserRole.master;
    }

    final user = UserModel(
      phone: phoneCtrl.text,
      name: nameCtrl.text.isNotEmpty
          ? nameCtrl.text
          : (role == UserRole.master ? t('role_master') : 'VIP Mijoz'),
      address: addressCtrl.text,
      role: role,
      masterTypeKey: role == UserRole.master ? selectedMasterTypeKey : null,
    );

    context.read<AppState>().setUser(user);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MainNavScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary, Color(0xFF1E293B)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // Language Selector
                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.language, color: Colors.white),
                          onPressed: _showLangPicker,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Logo
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.apartment,
                        size: 50,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Title
                    Text(
                      isLogin ? t('welcome_back') : t('create_account'),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isLogin ? 'Hisobingizga kiring' : 'Yangi hisob oching',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Glass Card
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isLogin) ...[
                            _buildTextField(
                              controller: nameCtrl,
                              hint: t('name'),
                              icon: Icons.person_outline,
                              validator: (v) =>
                                  v?.isEmpty ?? true ? t('fill_fields') : null,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: addressCtrl,
                              hint: t('address'),
                              icon: Icons.location_on_outlined,
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _buildRadioTile(
                                        'role_client', 'role_client'),
                                  ),
                                  Expanded(
                                    child: _buildRadioTile(
                                        'role_master', 'role_master'),
                                  ),
                                ],
                              ),
                            ),
                            if (selectedRoleKey == 'role_master') ...[
                              const SizedBox(height: 16),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: selectedMasterTypeKey,
                                    icon: const Icon(Icons.arrow_drop_down,
                                        color: AppColors.primary),
                                    items: masterTypesKeys.map((key) {
                                      return DropdownMenuItem(
                                        value: key,
                                        child: Text(t(key),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w500)),
                                      );
                                    }).toList(),
                                    onChanged: (v) => setState(
                                        () => selectedMasterTypeKey = v!),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                          ],

                          _buildTextField(
                            controller: phoneCtrl,
                            hint: t('phone'),
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            validator: (v) {
                              if (v?.isEmpty ?? true) return t('fill_fields');
                              if (v!.length < 9) return t('phone_error');
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          _buildTextField(
                            controller: passCtrl,
                            hint: t('pass'),
                            icon: Icons.lock_outline,
                            isPassword: true,
                            validator: (v) {
                              if (v?.isEmpty ?? true) return t('fill_fields');
                              if (!isLogin && v!.length < 8)
                                return t('password_short');
                              return null;
                            },
                          ),

                          if (!isLogin) ...[
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: confirmPassCtrl,
                              hint: t('pass2'),
                              icon: Icons.lock_outline,
                              isPassword: true,
                              validator: (v) {
                                if (v != passCtrl.text)
                                  return t('password_match');
                                return null;
                              },
                            ),
                          ],

                          const SizedBox(height: 28),

                          // Gradient Button
                          Container(
                            width: double.infinity,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppColors.primary, AppColors.accent],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _loginOrRegister,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                              child: Text(
                                t(isLogin ? 'login_btn' : 'reg_btn'),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Switch Auth Mode
                          Center(
                            child: TextButton(
                              onPressed: () =>
                                  setState(() => isLogin = !isLogin),
                              child: Text(
                                t(isLogin ? 'no_acc' : 'have_acc'),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword ? isPasswordHidden : false,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  isPasswordHidden ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.textSecondary,
                ),
                onPressed: () =>
                    setState(() => isPasswordHidden = !isPasswordHidden),
              )
            : null,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
    );
  }

  Widget _buildRadioTile(String value, String titleKey) {
    return RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      title: Text(
        t(titleKey),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: selectedRoleKey == value
              ? AppColors.primary
              : AppColors.textSecondary,
        ),
      ),
      value: value,
      groupValue: selectedRoleKey,
      activeColor: AppColors.primary,
      onChanged: (v) => setState(() => selectedRoleKey = v!),
    );
  }

  void _showLangPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Tilni tanlang / Выберите язык',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            _buildLangOption('O\'zbekcha (Lotin)', 'uz_lat'),
            _buildLangOption('Ўзбекча (Кирилл)', 'uz_cyr'),
            _buildLangOption('Русский', 'ru'),
          ],
        ),
      ),
    );
  }

  Widget _buildLangOption(String title, String langCode) {
    final isSelected = context.read<AppState>().lang == langCode;
    return ListTile(
      leading: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.accent : Colors.grey.shade400,
            width: 2,
          ),
          color: isSelected
              ? AppColors.accent.withOpacity(0.1)
              : Colors.transparent,
        ),
        child: isSelected
            ? const Center(
                child: Icon(Icons.check, size: 16, color: AppColors.accent),
              )
            : null,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppColors.primary : AppColors.textPrimary,
        ),
      ),
      onTap: () {
        context.read<AppState>().setLang(langCode);
        Navigator.pop(context);
      },
    );
  }
}

// ==========================================
// 10. ASOSIY NAVIGATSIYA (Modern)
// ==========================================
class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      extendBody: true,
      drawer: _buildModernDrawer(appState),
      body: IndexedStack(
        index: _idx,
        children: const [
          HomeScreen(),
          ProductsScreen(),
          UstalarCategoriesScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BottomNavigationBar(
            currentIndex: _idx,
            onTap: (i) {
              if (i == 4) {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CartScreen()));
                return;
              }
              setState(() => _idx = i);
            },
            backgroundColor: Colors.transparent,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: AppColors.accent,
            unselectedItemColor: Colors.grey.shade400,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            selectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
            items: [
              _buildNavItem(Icons.home_rounded, t('home')),
              _buildNavItem(Icons.grid_view_rounded, t('catalog')),
              _buildNavItem(Icons.handyman_rounded, t('masters')),
              _buildNavItem(Icons.person_rounded, t('profile')),
              BottomNavigationBarItem(
                icon: Consumer<CartProvider>(
                  builder: (context, cart, _) => Stack(
                    children: [
                      const Icon(Icons.shopping_bag_rounded),
                      if (!cart.isEmpty)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                                minWidth: 14, minHeight: 14),
                            child: Text(
                              '${cart.count}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                label: t('cart'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  BottomNavigationBarItem _buildNavItem(IconData icon, String label) {
    return BottomNavigationBarItem(icon: Icon(icon), label: label);
  }

  Widget _buildModernDrawer(AppState appState) {
    final user = appState.currentUser;

    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary, Color(0xFF1E293B)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withOpacity(0.3), width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.white,
                        backgroundImage: user?.avatar.isNotEmpty ?? false
                            ? NetworkImage(user!.avatar)
                            : null,
                        child: user?.avatar.isEmpty ?? true
                            ? const Icon(Icons.person,
                                size: 40, color: AppColors.primary)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.isAdmin ?? false
                          ? t('admin')
                          : (user?.name ?? 'User'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user != null ? '+998 ${user.phone}' : '',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildDrawerItem(Icons.home_rounded, t('home'), 0),
                      _buildDrawerItem(
                          Icons.grid_view_rounded, t('catalog'), 1),
                      _buildDrawerItem(Icons.handyman_rounded, t('masters'), 2),
                      _buildDrawerItem(Icons.history_rounded, t('history'), -1,
                          onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const OrderHistoryScreen()));
                      }),
                      const Divider(height: 32),
                      _buildDrawerItem(Icons.phone_rounded, t('contact'), -1,
                          onTap: () {
                        Navigator.pop(context);
                        _showContactDialog();
                      }),
                      _buildDrawerItem(
                          Icons.settings_rounded, t('settings'), -1, onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SettingsScreen()));
                      }),
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          leading:
                              const Icon(Icons.logout, color: AppColors.error),
                          title: const Text(
                            'Chiqish',
                            style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600),
                          ),
                          onTap: () {
                            context.read<AppState>().logout();
                            Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AuthScreen()));
                          },
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
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, int index,
      {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _idx == index
            ? AppColors.accent.withOpacity(0.1)
            : Colors.transparent,
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: _idx == index ? AppColors.accent : AppColors.textSecondary,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: _idx == index ? FontWeight.bold : FontWeight.w500,
            color: _idx == index ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: onTap ??
            () {
              Navigator.pop(context);
              setState(() => _idx = index);
            },
      ),
    );
  }

  void _showContactDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone_in_talk,
                    size: 40, color: AppColors.accent),
              ),
              const SizedBox(height: 16),
              const Text(
                'Aloqa uchun',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Biz bilan bog\'laning',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              _buildContactTile('+998 55 500 00 03', Icons.phone),
              const SizedBox(height: 12),
              _buildContactTile('+998 99 607 77 55', Icons.phone_android),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Yopish'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactTile(String phone, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.accent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              phone,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
        ],
      ),
    );
  }
}

// ==========================================
// 11. ZAMONAVIY HOME EKRAN
// ==========================================
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Modern App Bar
        SliverToBoxAdapter(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, Color(0xFF2C5282)],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Turon Beton',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Premium Beton',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.notifications_none,
                              color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Promo Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.2),
                            Colors.white.withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'YANGI',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  t('promo_sub'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.rocket_launch_rounded,
                            size: 50,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Masters Section
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const UstalarCategoriesScreen()),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00BFA5), Color(0xFF00897B)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('find_masters'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t('find_masters_sub'),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Topish →',
                              style: TextStyle(
                                color: Color(0xFF00897B),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.engineering,
                      size: 80,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Products Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  t('popular'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: Text(
                    t('all'),
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Products Grid
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.75,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final product = globalProducts[index];
                return _buildProductCard(context, product);
              },
              childCount: globalProducts.length,
            ),
          ),
        ),

        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  Widget _buildProductCard(BuildContext context, ProductModel product) {
    return GestureDetector(
      onTap: () => _openCalculator(context, product.id),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: Stack(
                  children: [
                    Image.network(
                      product.image,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade200,
                        child: Icon(product.icon, size: 40, color: Colors.grey),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_shopping_cart,
                          size: 20,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(product.nameKey),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hisoblash →',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'Tanlash',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 12. KATALOG EKRANI (Grid)
// ==========================================
class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: AppColors.primary,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                t('catalog'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, Color(0xFF2C5282)],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                childAspectRatio: 0.8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final product = globalProducts[index];
                  return _buildCatalogCard(context, product);
                },
                childCount: globalProducts.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogCard(BuildContext context, ProductModel product) {
    return GestureDetector(
      onTap: () => _openCalculator(context, product.id),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                product.image,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade300,
                  child: Icon(product.icon, size: 50, color: Colors.grey),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t(product.nameKey),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Hisoblash',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
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
    );
  }
}

// ==========================================
// 13. HISOBLAGICHLAR (Modern Bottom Sheet)
// ==========================================
void _openCalculator(BuildContext context, String id) {
  if (id == 'beton') {
    _showBetonCalculator(context);
  } else if (id == 'plita') {
    _showPlitaCalculator(context);
  } else if (id == 'stolba') {
    _showStolbaCalculator(context);
  } else if (id == 'kolodes') {
    _showUniversalCalculator(context, t('prod_kolodes'), {
      "КС 10-9": 250000,
      "КС 10-6": 200000,
      "КС 15-9": 500000,
      "KC 15-6": 400000
    });
  } else if (id == 'blok') {
    _showUniversalCalculator(context, t('prod_blok'),
        {"24-6-4": 220000, "12-6-4": 140000, "9-6-4": 100000});
  } else if (id == 'qopqoq') {
    _showUniversalCalculator(
        context, t('prod_qopqoq'), {"ПП 10*10": 250000, "ПП 15*15": 500000});
  } else if (id == 'lyuk') {
    _showUniversalCalculator(
        context, t('prod_lyuk'), {"ПП 10*10": 900000, "ПП 15*15": 1300000});
  }
}

void _showBetonCalculator(BuildContext context) {
  final Map<String, double> betonPrices = {
    "B7.5 M100": 350000,
    "B10 M150": 380000,
    "B15 M200": 420000,
    "B20 M250": 460000,
    "B22.5 M300": 500000,
    "B25 M350": 540000,
    "B30 M400": 560000,
    "B35 M450": 600000,
    "B40 M500": 640000,
    "B40 M550": 680000,
    "B45 M600": 720000,
    "B50 M650": 760000,
    "B55 M700": 800000
  };

  String selectedMarka = "B15 M200";
  int kub = 1;
  final kmCtrl = TextEditingController();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final pricePerKub = betonPrices[selectedMarka]!;
          final km = double.tryParse(kmCtrl.text) ?? 0.0;
          final betonSum = pricePerKub * kub;
          final dostavkaSum = km * 20000;
          final totalSum = betonSum + dostavkaSum;

          return Container(
            margin: const EdgeInsets.only(top: 50),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.local_shipping,
                                  color: AppColors.accent),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Text(
                                'Tayyor Beton',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Dropdown
                        _buildDropdown(
                          label: 'Beton markasi',
                          value: selectedMarka,
                          items: betonPrices.keys
                              .map(
                                (k) => DropdownMenuItem(
                                  value: k,
                                  child: Text(
                                      '$k - ${betonPrices[k]!.toStringAsFixed(0)} so\'m'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setModalState(() => selectedMarka = v!),
                        ),

                        const SizedBox(height: 20),

                        // Counter
                        _buildCounter(
                          label: 'Hajmi (kub)',
                          value: kub,
                          onDecrement: () {
                            if (kub > 1) setModalState(() => kub--);
                          },
                          onIncrement: () => setModalState(() => kub++),
                        ),

                        const SizedBox(height: 20),

                        // Distance
                        TextField(
                          controller: kmCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setModalState(() {}),
                          decoration: _modernInputDecoration(
                              'Masofa (km)', Icons.map_outlined),
                        ),

                        const SizedBox(height: 24),

                        // Summary Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, Color(0xFF2C5282)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            children: [
                              _buildPriceRow('Beton:', betonSum),
                              const SizedBox(height: 8),
                              _buildPriceRow('Yetkazib berish:', dostavkaSum,
                                  isDim: true),
                              const Divider(color: Colors.white30, height: 24),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'JAMI:',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${totalSum.toStringAsFixed(0)} so\'m',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Add Button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add_shopping_cart),
                            label: const Text(
                              'Savatga qo\'shish',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: () {
                              final item = CartItem(
                                id: DateTime.now()
                                    .millisecondsSinceEpoch
                                    .toString(),
                                name: t('prod_beton'),
                                details: '$selectedMarka\n🚚 Masofa: $km KM',
                                qty: kub,
                                price: pricePerKub,
                                dostavka: dostavkaSum,
                              );
                              context.read<CartProvider>().addItem(item);
                              Navigator.pop(context);
                              _showSuccessSnackBar(
                                  context, 'Savatga qo\'shildi!');
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

void _showUniversalCalculator(
    BuildContext context, String title, Map<String, double> pricesMap) {
  String selectedType = pricesMap.keys.first;
  int quantity = 1;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final unitPrice = pricesMap[selectedType]!;
          final totalSum = unitPrice * quantity;

          return _buildBottomSheetWrapper(
            title: title,
            icon: Icons.view_in_ar,
            child: Column(
              children: [
                _buildDropdown(
                  label: 'Turi',
                  value: selectedType,
                  items: pricesMap.keys
                      .map(
                        (k) => DropdownMenuItem(
                          value: k,
                          child: Text(
                              '$k - ${pricesMap[k]!.toStringAsFixed(0)} so\'m'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setModalState(() => selectedType = v!),
                ),
                const SizedBox(height: 20),
                _buildCounter(
                  label: 'Soni (dona)',
                  value: quantity,
                  onDecrement: () {
                    if (quantity > 1) setModalState(() => quantity--);
                  },
                  onIncrement: () => setModalState(() => quantity++),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      _buildPriceRow('1 dona narxi:', unitPrice),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'JAMI:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            '${totalSum.toStringAsFixed(0)} so\'m',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildAddButton(() {
                  final item = CartItem(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: title,
                    details: selectedType,
                    qty: quantity,
                    price: unitPrice,
                  );
                  context.read<CartProvider>().addItem(item);
                  Navigator.pop(context);
                  _showSuccessSnackBar(context, 'Savatga qo\'shildi!');
                }),
              ],
            ),
          );
        },
      );
    },
  );
}

void _showStolbaCalculator(BuildContext context) {
  final Map<String, double> pricesMap = {
    "Бетон столба СВ-110": 1100000,
    "Бетон столба СВ-95": 1000000
  };
  final Map<String, String> lengthMap = {
    "Бетон столба СВ-110": "11",
    "Бетон столба СВ-95": "9"
  };

  String selectedType = "Бетон столба СВ-110";
  int quantity = 1;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final unitPrice = pricesMap[selectedType]!;
          final totalSum = unitPrice * quantity;

          return _buildBottomSheetWrapper(
            title: t('prod_stolba'),
            icon: Icons.format_align_center,
            child: Column(
              children: [
                _buildDropdown(
                  label: 'Turi',
                  value: selectedType,
                  items: pricesMap.keys
                      .map(
                        (k) => DropdownMenuItem(value: k, child: Text(k)),
                      )
                      .toList(),
                  onChanged: (v) => setModalState(() => selectedType = v!),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.straighten, color: AppColors.accent),
                      const SizedBox(width: 12),
                      Text(
                        'Uzunligi: ${lengthMap[selectedType]} metr',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildCounter(
                  label: 'Soni (dona)',
                  value: quantity,
                  onDecrement: () {
                    if (quantity > 1) setModalState(() => quantity--);
                  },
                  onIncrement: () => setModalState(() => quantity++),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, Color(0xFF2C5282)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'JAMI:',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${totalSum.toStringAsFixed(0)} so\'m',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildAddButton(() {
                  final item = CartItem(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: t('prod_stolba'),
                    details: selectedType,
                    qty: quantity,
                    meters: lengthMap[selectedType],
                    price: unitPrice,
                  );
                  context.read<CartProvider>().addItem(item);
                  Navigator.pop(context);
                  _showSuccessSnackBar(context, 'Savatga qo\'shildi!');
                }),
              ],
            ),
          );
        },
      );
    },
  );
}

void _showPlitaCalculator(BuildContext context) {
  int selectedWire = 12;
  int quantity = 1;
  final lengthCtrl = TextEditingController();

  final Map<int, double> wirePrices = {
    12: 185000,
    13: 190000,
    15: 200000,
    16: 210000,
    18: 220000
  };

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final length =
              double.tryParse(lengthCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final pricePerMeter = wirePrices[selectedWire]!;
          final unitPrice = length * pricePerMeter;
          final totalPrice = unitPrice * quantity;

          return _buildBottomSheetWrapper(
            title: 'Plita PK',
            icon: Icons.view_comfy_alt,
            child: Column(
              children: [
                TextField(
                  controller: lengthCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setModalState(() {}),
                  decoration: _modernInputDecoration(
                      'Uzunligi (metr)', Icons.straighten),
                ),
                const SizedBox(height: 20),
                _buildDropdown(
                  label: 'Simlar soni',
                  value: selectedWire,
                  items: wirePrices.keys
                      .map(
                        (wire) => DropdownMenuItem(
                          value: wire,
                          child: Text(
                              '$wire talik sim - ${wirePrices[wire]} so\'m/m'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setModalState(() => selectedWire = v!),
                ),
                const SizedBox(height: 20),
                _buildCounter(
                  label: 'Soni (dona)',
                  value: quantity,
                  onDecrement: () {
                    if (quantity > 1) setModalState(() => quantity--);
                  },
                  onIncrement: () => setModalState(() => quantity++),
                ),
                const SizedBox(height: 24),
                if (length > 0)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        _buildPriceRow('1 dona narxi:', unitPrice),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'JAMI:',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '${totalPrice.toStringAsFixed(0)} so\'m',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                _buildAddButton(() {
                  if (length <= 0) {
                    _showErrorSnackBar(context, 'Uzunlikni kiriting!');
                    return;
                  }
                  final item = CartItem(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: 'Plita PK',
                    details: '$selectedWire talik sim',
                    qty: quantity,
                    meters: length.toString(),
                    price: unitPrice,
                  );
                  context.read<CartProvider>().addItem(item);
                  Navigator.pop(context);
                  _showSuccessSnackBar(context, 'Savatga qo\'shildi!');
                }),
              ],
            ),
          );
        },
      );
    },
  );
}

// Helper widgets for calculators
Widget _buildBottomSheetWrapper(
    {required String title, required IconData icon, required Widget child}) {
  return Container(
    margin: const EdgeInsets.only(top: 50),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: AppColors.accent),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                child,
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildDropdown<T>({
  required String label,
  required T value,
  required List<DropdownMenuItem<T>> items,
  required void Function(T?) onChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isExpanded: true,
            value: value,
            icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    ],
  );
}

Widget _buildCounter({
  required String label,
  required int value,
  required VoidCallback onDecrement,
  required VoidCallback onIncrement,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline,
                  color: AppColors.error),
              onPressed: onDecrement,
            ),
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            IconButton(
              icon:
                  const Icon(Icons.add_circle_outline, color: AppColors.accent),
              onPressed: onIncrement,
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _buildPriceRow(String label, double value, {bool isDim = false}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          color: isDim ? Colors.white70 : Colors.white,
          fontSize: 16,
        ),
      ),
      Text(
        '${value.toStringAsFixed(0)} so\'m',
        style: TextStyle(
          color: isDim ? Colors.white70 : Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

Widget _buildAddButton(VoidCallback onPressed) {
  return SizedBox(
    width: double.infinity,
    height: 56,
    child: ElevatedButton.icon(
      icon: const Icon(Icons.add_shopping_cart),
      label: const Text(
        'Savatga qo\'shish',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onPressed,
    ),
  );
}

InputDecoration _modernInputDecoration(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, color: AppColors.textSecondary),
    filled: true,
    fillColor: Colors.grey.shade50,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: Colors.grey.shade200),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.accent, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
  );
}

void _showSuccessSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 12),
          Text(message),
        ],
      ),
      backgroundColor: AppColors.secondary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ),
  );
}

void _showErrorSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white),
          const SizedBox(width: 12),
          Text(message),
        ],
      ),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ),
  );
}

// ==========================================
// 14. USTALAR BOZORI (Modern)
// ==========================================
class UstalarCategoriesScreen extends StatelessWidget {
  const UstalarCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            floating: true,
            pinned: true,
            backgroundColor: AppColors.primary,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(t('masters')),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, Color(0xFF2C5282)],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                t('choose_prof'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.1,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final key = masterTypesKeys[index];
                  final count =
                      mastersDatabase.where((m) => m['typeKey'] == key).length;
                  return _buildMasterCategoryCard(context, key, count);
                },
                childCount: masterTypesKeys.length,
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }

  Widget _buildMasterCategoryCard(BuildContext context, String key, int count) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => MastersListScreen(categoryKey: key)),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.handyman,
                size: 32,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t(key),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count ${t('masters_count')}',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MastersListScreen extends StatelessWidget {
  final String categoryKey;
  const MastersListScreen({super.key, required this.categoryKey});

  @override
  Widget build(BuildContext context) {
    final filteredMasters =
        mastersDatabase.where((m) => m['typeKey'] == categoryKey).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: AppColors.primary,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(t(categoryKey)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, Color(0xFF2C5282)],
                  ),
                ),
              ),
            ),
          ),
          if (filteredMasters.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'Hozircha ustalar yo\'q',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final master = filteredMasters[index];
                    return _buildMasterCard(context, master);
                  },
                  childCount: filteredMasters.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMasterCard(BuildContext context, Map<String, String> master) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accent, Color(0xFF00897B)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    master['name']!,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text(
                        master['address']!,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 16, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        master['rating']!,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(Icons.phone, color: AppColors.accent),
                onPressed: () => _showCallDialog(context, master),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCallDialog(BuildContext context, Map<String, String> master) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone_in_talk,
                    size: 40, color: AppColors.accent),
              ),
              const SizedBox(height: 16),
              Text(
                master['name']!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  master['phone']!,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Yopish'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Qo\'ng\'iroq'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 15. PROFIL (Modern)
// ==========================================
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, Color(0xFF2C5282)],
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Container(
                height: 60,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: user?.avatar.isNotEmpty ?? false
                            ? NetworkImage(user!.avatar)
                            : null,
                        child: user?.avatar.isEmpty ?? true
                            ? const Icon(Icons.person,
                                size: 50, color: Colors.grey)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.isAdmin ?? false
                          ? t('admin')
                          : (user?.name ?? 'User'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        user != null ? '+998 ${user.phone}' : '',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildProfileCard(
                      icon: Icons.edit,
                      title: t('edit_prof'),
                      color: Colors.blue,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const EditProfileScreen())),
                    ),
                    const SizedBox(height: 12),
                    _buildProfileCard(
                      icon: Icons.history,
                      title: t('history'),
                      color: Colors.orange,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const OrderHistoryScreen())),
                    ),
                    const SizedBox(height: 12),
                    _buildProfileCard(
                      icon: Icons.settings,
                      title: t('settings'),
                      color: Colors.purple,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen())),
                    ),
                    const SizedBox(height: 12),
                    _buildProfileCard(
                      icon: Icons.logout,
                      title: 'Chiqish',
                      color: Colors.red,
                      onTap: () {
                        context.read<AppState>().logout();
                        Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const AuthScreen()));
                      },
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        trailing:
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}

// EditProfile va Settings o'zgarishsiz, lekin zamonaviy ko'rinishda
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController nameCtrl;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().currentUser;
    nameCtrl = TextEditingController(text: user?.name ?? '');
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title:
            Text(t('edit_prof'), style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage:
                        appState.currentUser?.avatar.isNotEmpty ?? false
                            ? NetworkImage(appState.currentUser!.avatar)
                            : null,
                    child: appState.currentUser?.avatar.isEmpty ?? true
                        ? Icon(Icons.person,
                            size: 60, color: Colors.grey.shade400)
                        : null,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            TextField(
              controller: nameCtrl,
              decoration: _modernInputDecoration(t('name'), Icons.person),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  final currentUser = appState.currentUser;
                  if (currentUser != null) {
                    final updatedUser = UserModel(
                      phone: currentUser.phone,
                      name: nameCtrl.text,
                      address: currentUser.address,
                      avatar: currentUser.avatar,
                      role: currentUser.role,
                      masterTypeKey: currentUser.masterTypeKey,
                    );
                    appState.setUser(updatedUser);
                  }
                  Navigator.pop(context);
                  _showSuccessSnackBar(context, 'Saqlandi!');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Saqlash',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(t('settings'), style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildSectionTitle(t('lang')),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              children: [
                _buildRadioTile(appState, 'O\'zbekcha (Lotin)', 'uz_lat'),
                const Divider(height: 1, indent: 20, endIndent: 20),
                _buildRadioTile(appState, 'Ўзбекча (Кирилл)', 'uz_cyr'),
                const Divider(height: 1, indent: 20, endIndent: 20),
                _buildRadioTile(appState, 'Русский', 'ru'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _buildSectionTitle('Tashqi ko\'rinish'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                ),
              ],
            ),
            child: SwitchListTile(
              title: const Text(
                'Tungi rejim',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Qorong\'i mavzuni yoqish',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              secondary: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.dark_mode, color: Colors.indigo),
              ),
              value: appState.theme == ThemeMode.dark,
              onChanged: (val) =>
                  appState.setTheme(val ? ThemeMode.dark : ThemeMode.light),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildRadioTile(AppState appState, String title, String langCode) {
    final isSelected = appState.lang == langCode;
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppColors.primary : AppColors.textPrimary,
        ),
      ),
      trailing: isSelected
          ? Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 16, color: Colors.white),
            )
          : null,
      onTap: () => appState.setLang(langCode),
    );
  }
}

// ==========================================
// 16. TARIX (Timeline Style)
// ==========================================
class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  List<Map<String, dynamic>> liveOrders = [];
  Timer? _timer;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchOrders());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchOrders() async {
    final user = context.read<AppState>().currentUser;
    if (user == null) return;

    final orders = await FirebaseService.fetchOrders(user.phone);
    if (mounted) {
      setState(() {
        liveOrders = orders;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(t('history'), style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : liveOrders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        'Hozircha buyurtmalar yo\'q',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: liveOrders.length,
                  itemBuilder: (context, index) {
                    final order = liveOrders[index];
                    return _buildOrderCard(order);
                  },
                ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status'];
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case 'JARAYONDA':
        statusColor = Colors.orange;
        statusIcon = Icons.autorenew;
        statusText = 'Jarayonda';
        break;
      case 'YETKAZIB BORILMOQDA':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Yetkazilmoqda';
        break;
      default:
        statusColor = Colors.blue;
        statusIcon = Icons.access_time;
        statusText = 'Kutilmoqda';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(statusIcon, size: 20, color: statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        order['date'],
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order['items'],
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Jami summa:',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${order['total']} so\'m',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 17. SAVATCHA (Modern Swipe)
// ==========================================
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: Text(t('cart'), style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: cart.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.shopping_bag_outlined,
                        size: 64, color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    t('empty'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mahsulotlar qo\'shing',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: cart.items.length,
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      return Dismissible(
                        key: Key(item.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => cart.removeItem(index),
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.inventory_2,
                                    color: AppColors.accent),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (item.details.isNotEmpty)
                                      Text(
                                        item.details,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${item.qty} x ${item.price.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${item.totalPrice.toStringAsFixed(0)} so\'m',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              t('total'),
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              '${cart.totalSum.toStringAsFixed(0)} so\'m',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        PaymentScreen(amount: cart.totalSum)),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            child: Text(
                              t('checkout'),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ==========================================
// 18. TO'LOV (Premium Design)
// ==========================================
class PaymentScreen extends StatefulWidget {
  final double amount;
  const PaymentScreen({super.key, required this.amount});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool isProcessing = false;

  Future<void> _confirmAndSendOrder() async {
    if (!AppConfig.isConfigured) {
      _showErrorSnackBar(context, t('config_error'));
      return;
    }

    setState(() => isProcessing = true);

    try {
      final appState = context.read<AppState>();
      final cart = context.read<CartProvider>();
      final user = appState.currentUser;

      if (user == null) throw Exception('Foydalanuvchi topilmadi');

      final order = OrderModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userName: user.name,
        userPhone: user.phone,
        userAddress: user.address,
        items: cart.items.toList(),
        totalAmount: widget.amount,
        date: DateTime.now(),
      );

      final orderId = await FirebaseService.sendOrder(order);

      if (orderId != null) {
        final telegramSent =
            await TelegramService.sendOrderNotification(order, orderId);

        if (telegramSent) {
          final excelBytes = ExcelService.generateOrderExcel(
            userName: user.name,
            userPhone: user.phone,
            userAddress: user.address,
            items: cart.items.toList(),
          );

          await TelegramService.sendExcelDocument(
            excelBytes,
            'Buyurtma_${user.name.replaceAll(' ', '_')}.xlsx',
            null,
          );

          cart.clear();

          if (mounted) {
            _showSuccessSnackBar(context, "Buyurtma yuborildi!");
            Navigator.popUntil(context, (route) => route.isFirst);
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const OrderHistoryScreen()));
          }
        }
      } else {
        throw Exception('Buyurtma saqlanmadi');
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar(context, 'Xatolik: $e');
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text("Buyurtmani tasdiqlash",
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isProcessing
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                      color: AppColors.accent, strokeWidth: 3),
                  const SizedBox(height: 24),
                  Text(
                    "Buyurtma yuborilmoqda...",
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  // Amount Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, Color(0xFF2C5282)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          'To\'lov summasi',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${widget.amount.toStringAsFixed(0)} so\'m',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Info Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.support_agent,
                            size: 40,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Operator orqali tasdiqlash',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Buyurtmangiz to\'g\'ridan-to\'g\'ri zavod bazasiga tushadi. Operatorlarimiz tez orada siz bilan bog\'lanib, to\'lov va yetkazib berishni tasdiqlaydi.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade600,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            _buildFeatureIcon(Icons.verified_user, 'Xavfsiz'),
                            _buildFeatureIcon(Icons.speed, 'Tezkor'),
                            _buildFeatureIcon(
                                Icons.headset_mic, 'Qo\'llab-quvvatlash'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Confirm Button
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.send_rounded),
                      label: const Text(
                        'Buyurtmani yuborish',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: _confirmAndSendOrder,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Buyurtma yuborilgach, siz bilan operatorimiz bog\'lanadi',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFeatureIcon(IconData icon, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: AppColors.accent, size: 28),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
