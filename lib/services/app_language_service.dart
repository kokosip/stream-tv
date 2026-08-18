import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLanguageService {
  static const String _key = 'app_language';
  
  // Default language is English ('en')
  static final ValueNotifier<String> currentLanguage = ValueNotifier<String>('en');

  /// Initialize language setting from SharedPreferences
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString(_key) ?? 'en';
    currentLanguage.value = lang;
  }

  /// Change language and persist to SharedPreferences
  static Future<void> setLanguage(String langCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, langCode);
    currentLanguage.value = langCode;
  }

  /// Helper to get text based on current language
  static String tr({required String en, required String id}) {
    return currentLanguage.value == 'id' ? id : en;
  }

  /// Check if active language is English
  static bool get isEnglish => currentLanguage.value == 'en';
}
