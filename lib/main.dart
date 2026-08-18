import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'services/app_language_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Restrict Flutter imageCache size to prevent Android TV Low Memory (OOM) killer crashes
  PaintingBinding.instance.imageCache.maximumSizeBytes = 40 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 100;

  MediaKit.ensureInitialized();
  await AppLanguageService.init();
  runApp(const MovieBoxTvApp());
}

class MovieBoxTvApp extends StatelessWidget {
  const MovieBoxTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLanguageService.currentLanguage,
      builder: (context, langCode, child) {
        return MaterialApp(
          title: 'MovieBox TV',
          debugShowCheckedModeBanner: false,
          locale: Locale(langCode),
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0F0F0F),
            primaryColor: Colors.redAccent.shade700,
            colorScheme: ColorScheme.dark(
              primary: Colors.redAccent.shade700,
              surface: const Color(0xFF1E1E1E),
            ),
            textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}
