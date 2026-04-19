// ==========================================
// CORE: State Management (Alohida fayl - circular import oldini olish uchun)
// ==========================================
import 'package:flutter/material.dart';
import 'package:turon_beton/models/models.dart';

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
