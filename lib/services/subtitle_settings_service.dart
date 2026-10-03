import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_language_service.dart';

class SubtitleSizeOption {
  final double size;
  final String nameEn;
  final String nameId;

  const SubtitleSizeOption({
    required this.size,
    required this.nameEn,
    required this.nameId,
  });

  String get name => AppLanguageService.tr(en: nameEn, id: nameId);
  String get label => '$name (${size.toInt()}px)';
}

class SubtitleSettingsService {
  static const String _keyFontSize = 'subtitle_font_size';
  static const String _keyFontColor = 'subtitle_font_color';
  static const String _keyHasBackground = 'subtitle_has_background';

  static const double defaultFontSize = 18.0;
  static const double minFontSize = 12.0;
  static const double maxFontSize = 36.0;
  static const double fontSizeStep = 2.0;
  static const Color defaultFontColor = Colors.white;

  /// Available preset sizes for quick selection
  static const List<SubtitleSizeOption> sizePresets = [
    SubtitleSizeOption(size: 12.0, nameEn: "Extra Small", nameId: "Sangat Kecil"),
    SubtitleSizeOption(size: 15.0, nameEn: "Small", nameId: "Kecil"),
    SubtitleSizeOption(size: 18.0, nameEn: "Normal (Default)", nameId: "Normal (Standar)"),
    SubtitleSizeOption(size: 22.0, nameEn: "Large", nameId: "Besar"),
    SubtitleSizeOption(size: 26.0, nameEn: "Extra Large", nameId: "Sangat Besar"),
    SubtitleSizeOption(size: 30.0, nameEn: "Huge", nameId: "Ekstra Besar"),
    SubtitleSizeOption(size: 34.0, nameEn: "Maximum", nameId: "Maksimal"),
  ];

  /// Supported subtitle text colors
  static const Map<String, Color> supportedColors = {
    'White': Colors.white,
    'Yellow': Colors.yellowAccent,
    'Cyan': Colors.cyanAccent,
    'Green': Colors.greenAccent,
    'Pink': Colors.pinkAccent,
    'Amber': Colors.amberAccent,
    'Orange': Colors.orangeAccent,
  };

  static final ValueNotifier<double> fontSizeNotifier = ValueNotifier<double>(defaultFontSize);
  static final ValueNotifier<Color> fontColorNotifier = ValueNotifier<Color>(defaultFontColor);
  static final ValueNotifier<bool> hasBackgroundNotifier = ValueNotifier<bool>(false);

  static double get fontSize => fontSizeNotifier.value;
  static Color get fontColor => fontColorNotifier.value;
  static bool get hasBackground => hasBackgroundNotifier.value;

  /// Get name of active preset or custom size
  static String get activePresetName {
    for (final preset in sizePresets) {
      if ((preset.size - fontSize).abs() < 0.5) {
        return preset.name;
      }
    }
    return '${fontSize.toInt()}px';
  }

  /// Initialize subtitle settings from SharedPreferences
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final savedFontSize = prefs.getDouble(_keyFontSize);
      if (savedFontSize != null && savedFontSize >= minFontSize && savedFontSize <= maxFontSize) {
        fontSizeNotifier.value = savedFontSize;
      }

      final savedColorValue = prefs.getInt(_keyFontColor);
      if (savedColorValue != null) {
        fontColorNotifier.value = Color(savedColorValue);
      }

      final savedHasBg = prefs.getBool(_keyHasBackground);
      if (savedHasBg != null) {
        hasBackgroundNotifier.value = savedHasBg;
      }
    } catch (e) {
      debugPrint("Error initializing SubtitleSettingsService: $e");
    }
  }

  /// Set and persist custom font size
  static Future<void> setFontSize(double size) async {
    final clamped = size.clamp(minFontSize, maxFontSize);
    fontSizeNotifier.value = clamped;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyFontSize, clamped);
    } catch (e) {
      debugPrint("Error saving subtitle font size: $e");
    }
  }

  /// Increase font size by step (default 2px)
  static Future<double> increaseFontSize({double step = fontSizeStep}) async {
    final newSize = (fontSizeNotifier.value + step).clamp(minFontSize, maxFontSize);
    await setFontSize(newSize);
    return newSize;
  }

  /// Decrease font size by step (default 2px)
  static Future<double> decreaseFontSize({double step = fontSizeStep}) async {
    final newSize = (fontSizeNotifier.value - step).clamp(minFontSize, maxFontSize);
    await setFontSize(newSize);
    return newSize;
  }

  /// Set and persist subtitle color
  static Future<void> setFontColor(Color color) async {
    fontColorNotifier.value = color;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyFontColor, color.toARGB32());
    } catch (e) {
      debugPrint("Error saving subtitle color: $e");
    }
  }

  /// Set and persist semi-transparent background box toggle
  static Future<void> setHasBackground(bool hasBg) async {
    hasBackgroundNotifier.value = hasBg;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyHasBackground, hasBg);
    } catch (e) {
      debugPrint("Error saving subtitle background preference: $e");
    }
  }

  /// Reset settings back to defaults
  static Future<void> resetToDefaults() async {
    await setFontSize(defaultFontSize);
    await setFontColor(defaultFontColor);
    await setHasBackground(false);
  }

  /// Get friendly localized label for a font size
  static String getSizeDescription(double size) {
    for (final preset in sizePresets) {
      if ((preset.size - size).abs() < 0.5) {
        return preset.label;
      }
    }
    return '${size.toInt()} px';
  }

  /// Get localized color name
  static String getColorName(Color color) {
    for (final entry in supportedColors.entries) {
      if (entry.value.toARGB32() == color.toARGB32()) {
        switch (entry.key) {
          case 'White':
            return AppLanguageService.tr(en: "White", id: "Putih");
          case 'Yellow':
            return AppLanguageService.tr(en: "Yellow", id: "Kuning");
          case 'Cyan':
            return AppLanguageService.tr(en: "Cyan", id: "Biru Cyan");
          case 'Green':
            return AppLanguageService.tr(en: "Green", id: "Hijau");
          case 'Pink':
            return AppLanguageService.tr(en: "Pink", id: "Merah Muda");
          case 'Amber':
            return AppLanguageService.tr(en: "Amber", id: "Kuning Emas");
          case 'Orange':
            return AppLanguageService.tr(en: "Orange", id: "Oranye");
          default:
            return entry.key;
        }
      }
    }
    return AppLanguageService.tr(en: "Custom", id: "Kustom");
  }
}
