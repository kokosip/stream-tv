import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_language_service.dart';
import '../services/subtitle_settings_service.dart';
import 'tv_focusable_card.dart';

class SubtitleCustomizationDialog extends StatefulWidget {
  const SubtitleCustomizationDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) => const SubtitleCustomizationDialog(),
    );
  }

  @override
  State<SubtitleCustomizationDialog> createState() => _SubtitleCustomizationDialogState();
}

class _SubtitleCustomizationDialogState extends State<SubtitleCustomizationDialog> {
  late double _currentFontSize;
  late Color _currentColor;
  late bool _hasBackground;

  final FocusNode _decreaseFocusNode = FocusNode();
  final FocusNode _increaseFocusNode = FocusNode();
  final FocusNode _resetFocusNode = FocusNode();
  final FocusNode _closeFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentFontSize = SubtitleSettingsService.fontSize;
    _currentColor = SubtitleSettingsService.fontColor;
    _hasBackground = SubtitleSettingsService.hasBackground;
  }

  @override
  void dispose() {
    _decreaseFocusNode.dispose();
    _increaseFocusNode.dispose();
    _resetFocusNode.dispose();
    _closeFocusNode.dispose();
    super.dispose();
  }

  void _changeFontSize(double newSize) {
    final clamped = newSize.clamp(
      SubtitleSettingsService.minFontSize,
      SubtitleSettingsService.maxFontSize,
    );
    setState(() {
      _currentFontSize = clamped;
    });
    SubtitleSettingsService.setFontSize(clamped);
  }

  void _changeColor(Color color) {
    setState(() {
      _currentColor = color;
    });
    SubtitleSettingsService.setFontColor(color);
  }

  void _toggleBackground(bool val) {
    setState(() {
      _hasBackground = val;
    });
    SubtitleSettingsService.setHasBackground(val);
  }

  void _reset() {
    setState(() {
      _currentFontSize = SubtitleSettingsService.defaultFontSize;
      _currentColor = SubtitleSettingsService.defaultFontColor;
      _hasBackground = false;
    });
    SubtitleSettingsService.resetToDefaults();
  }

  @override
  Widget build(BuildContext context) {
    final isTv = MediaQuery.of(context).size.width > 800;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: isTv ? 64 : 16,
          vertical: isTv ? 32 : 16,
        ),
        child: Container(
          width: isTv ? 680 : double.infinity,
          constraints: const BoxConstraints(maxHeight: 640),
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2A2A2A), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFF262626))),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.format_size_rounded, color: Colors.redAccent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLanguageService.tr(
                              en: "Subtitle Appearance",
                              id: "Tampilan Huruf Subtitle",
                            ),
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            AppLanguageService.tr(
                              en: "Customize font size, color & readability",
                              id: "Sesuaikan ukuran huruf, warna & keterbacaan",
                            ),
                            style: GoogleFonts.outfit(
                              color: Colors.grey.shade400,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // 2. Scrollable Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // LIVE PREVIEW CARD
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0A0A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF222222)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    AppLanguageService.tr(en: "LIVE PREVIEW", id: "PRATINJAU LANGSUNG"),
                                    style: GoogleFonts.outfit(
                                      color: Colors.redAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                                Text(
                                  SubtitleSettingsService.getSizeDescription(_currentFontSize),
                                  style: GoogleFonts.outfit(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Container(
                              padding: _hasBackground
                                  ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
                                  : EdgeInsets.zero,
                              decoration: _hasBackground
                                  ? BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.75),
                                      borderRadius: BorderRadius.circular(8),
                                    )
                                  : null,
                              child: Text(
                                AppLanguageService.tr(
                                  en: "This is sample subtitle text.\nAdjust size to make it bigger or smaller.",
                                  id: "Ini contoh kalimat teks subtitle.\nAtur ukuran untuk membesarkan atau mengecilkan.",
                                ),
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(
                                  fontSize: _currentFontSize,
                                  color: _currentColor,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(
                                      offset: const Offset(-1.5, -1.5),
                                      color: Colors.black.withValues(alpha: 0.9),
                                    ),
                                    Shadow(
                                      offset: const Offset(1.5, -1.5),
                                      color: Colors.black.withValues(alpha: 0.9),
                                    ),
                                    Shadow(
                                      offset: const Offset(-1.5, 1.5),
                                      color: Colors.black.withValues(alpha: 0.9),
                                    ),
                                    Shadow(
                                      offset: const Offset(1.5, 1.5),
                                      color: Colors.black.withValues(alpha: 0.9),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // FONT SIZE STEPPER CONTROLS
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AppLanguageService.tr(en: "Font Size", id: "Ukuran Huruf"),
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              // Decrease Button (-)
                              TvFocusableCard(
                                focusNode: _decreaseFocusNode,
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => _changeFontSize(_currentFontSize - SubtitleSettingsService.fontSizeStep),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF222222),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF333333)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.remove, color: Colors.white, size: 18),
                                      const SizedBox(width: 4),
                                      Text(
                                        AppLanguageService.tr(en: "Smaller", id: "Kecilkan"),
                                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Increase Button (+)
                              TvFocusableCard(
                                focusNode: _increaseFocusNode,
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => _changeFontSize(_currentFontSize + SubtitleSettingsService.fontSizeStep),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF222222),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF333333)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.add, color: Colors.white, size: 18),
                                      const SizedBox(width: 4),
                                      Text(
                                        AppLanguageService.tr(en: "Bigger", id: "Besarkan"),
                                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // PRESET SIZE CHIPS
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: SubtitleSettingsService.sizePresets.map((preset) {
                          final isSelected = (_currentFontSize - preset.size).abs() < 0.5;
                          return TvFocusableCard(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _changeFontSize(preset.size),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.redAccent.shade700 : const Color(0xFF202020),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? Colors.redAccent : const Color(0xFF333333),
                                ),
                              ),
                              child: Text(
                                preset.label,
                                style: GoogleFonts.outfit(
                                  color: isSelected ? Colors.white : Colors.grey.shade300,
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 18),

                      // COLOR SELECTION
                      Text(
                        AppLanguageService.tr(en: "Subtitle Color", id: "Warna Subtitle"),
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: SubtitleSettingsService.supportedColors.entries.map((entry) {
                          final isSelected = _currentColor.toARGB32() == entry.value.toARGB32();
                          final colorName = SubtitleSettingsService.getColorName(entry.value);
                          return TvFocusableCard(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _changeColor(entry.value),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF2D1616) : const Color(0xFF202020),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? Colors.redAccent : const Color(0xFF333333),
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: entry.value,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white38),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    colorName,
                                    style: GoogleFonts.outfit(
                                      color: isSelected ? Colors.redAccent : Colors.white,
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 16),

                      // BACKGROUND BOX TOGGLE
                      TvFocusableCard(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _toggleBackground(!_hasBackground),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF202020),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF333333)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _hasBackground ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                color: _hasBackground ? Colors.redAccent : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLanguageService.tr(
                                        en: "Dark Background Box",
                                        id: "Latar Belakang Gelap",
                                      ),
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      AppLanguageService.tr(
                                        en: "Adds a dark translucent background for better contrast",
                                        id: "Menambahkan kotak gelap transparan agar lebih mudah dibaca",
                                      ),
                                      style: GoogleFonts.outfit(
                                        color: Colors.grey.shade400,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
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

              // 3. Footer Action Buttons
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFF262626))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TvFocusableCard(
                      focusNode: _resetFocusNode,
                      borderRadius: BorderRadius.circular(10),
                      onTap: _reset,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(
                          AppLanguageService.tr(en: "Reset to Default", id: "Atur Ulang"),
                          style: GoogleFonts.outfit(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    TvFocusableCard(
                      focusNode: _closeFocusNode,
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.shade700,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          AppLanguageService.tr(en: "Done", id: "Selesai"),
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
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
    );
  }
}
