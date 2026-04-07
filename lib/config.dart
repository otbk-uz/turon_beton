// ==========================================
// 1. KONFIGURATSIYA (Xavfsiz)
// ==========================================
class AppConfig {
  static const String botToken =
      String.fromEnvironment('BOT_TOKEN', defaultValue: 'YOUR_BOT_TOKEN');
  static const String chatId =
      String.fromEnvironment('CHAT_ID', defaultValue: 'YOUR_CHAT_ID');
  static const String firebaseUrl = String.fromEnvironment('FIREBASE_URL',
      defaultValue: 'https://your-project.firebaseio.com/orders.json');
  static bool get isConfigured =>
      botToken != 'YOUR_BOT_TOKEN' && chatId != 'YOUR_CHAT_ID';
}
