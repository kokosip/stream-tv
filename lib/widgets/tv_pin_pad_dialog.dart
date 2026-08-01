import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tv_focusable_card.dart';

/// TV-optimized dialog to set a new 4-digit passcode.
class SetPasscodeDialog extends StatefulWidget {
  const SetPasscodeDialog({super.key});

  @override
  State<SetPasscodeDialog> createState() => _SetPasscodeDialogState();
}

class _SetPasscodeDialogState extends State<SetPasscodeDialog> {
  final FocusNode _button1FocusNode = FocusNode();
  int _step = 0; // 0 = Enter initial passcode, 1 = Confirm passcode
  String _pin1 = '';
  String _pin2 = '';
  String _errorMessage = '';

  String get _currentPin => _step == 0 ? _pin1 : _pin2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _button1FocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _button1FocusNode.dispose();
    super.dispose();
  }

  void _onNumTap(String num) {
    setState(() {
      _errorMessage = '';
      if (_step == 0) {
        if (_pin1.length < 4) {
          _pin1 += num;
          if (_pin1.length == 4) {
            Future.delayed(const Duration(milliseconds: 180), () {
              if (mounted) {
                setState(() {
                  _step = 1;
                });
                _button1FocusNode.requestFocus();
              }
            });
          }
        }
      } else {
        if (_pin2.length < 4) {
          _pin2 += num;
          if (_pin2.length == 4) {
            _verifyAndSave();
          }
        }
      }
    });
  }

  void _onBackspace() {
    setState(() {
      _errorMessage = '';
      if (_step == 0) {
        if (_pin1.isNotEmpty) {
          _pin1 = _pin1.substring(0, _pin1.length - 1);
        }
      } else {
        if (_pin2.isNotEmpty) {
          _pin2 = _pin2.substring(0, _pin2.length - 1);
        } else {
          _step = 0;
          _pin1 = '';
          _button1FocusNode.requestFocus();
        }
      }
    });
  }

  void _onClear() {
    setState(() {
      _errorMessage = '';
      if (_step == 0) {
        _pin1 = '';
      } else {
        _pin2 = '';
      }
      _button1FocusNode.requestFocus();
    });
  }

  Future<void> _verifyAndSave() async {
    if (_pin1.length != 4) {
      setState(() {
        _errorMessage = 'Passcode must be 4 digits';
        _step = 0;
        _pin1 = '';
        _pin2 = '';
      });
      _button1FocusNode.requestFocus();
      return;
    }

    if (_pin1 != _pin2) {
      setState(() {
        _errorMessage = 'Passcodes do not match. Try again.';
        _step = 0;
        _pin1 = '';
        _pin2 = '';
      });
      _button1FocusNode.requestFocus();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nsfw_passcode', _pin1);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
        _onNumTap('0');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
        _onNumTap('1');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
        _onNumTap('2');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
        _onNumTap('3');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
        _onNumTap('4');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
        _onNumTap('5');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
        _onNumTap('6');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
        _onNumTap('7');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
        _onNumTap('8');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
        _onNumTap('9');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
        _onBackspace();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleKeyEvent,
      child: PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: const Color(0xFF161616),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2C2C2C)),
          ),
          child: Container(
            width: 360,
            padding: const EdgeInsets.all(24),
            child: FocusTraversalGroup(
              policy: WidgetOrderTraversalPolicy(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.security,
                    color: Colors.redAccent.shade700,
                    size: 44,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _step == 0 ? "Set NSFW Passcode" : "Confirm Passcode",
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _step == 0
                        ? "Use your remote to enter a 4-digit passcode."
                        : "Re-enter the passcode to confirm.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.grey.shade400,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // PIN indicator slots
                  _buildPinDisplay(_currentPin),
                  const SizedBox(height: 12),

                  // Error State
                  if (_errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _errorMessage,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                  // On-Screen Keypad Grid
                  _buildKeypadGrid(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinDisplay(String pin) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final isFilled = index < pin.length;
        final isCurrent = index == pin.length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 48,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isFilled
                  ? Colors.redAccent.shade700
                  : isCurrent
                      ? Colors.redAccent.withOpacity(0.5)
                      : const Color(0xFF333333),
              width: isFilled || isCurrent ? 2 : 1,
            ),
            boxShadow: isFilled
                ? [
                    BoxShadow(
                      color: Colors.redAccent.shade700.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: isFilled
              ? Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.shade700,
                    shape: BoxShape.circle,
                  ),
                )
              : Text(
                  "-",
                  style: GoogleFonts.outfit(
                    color: Colors.grey.shade600,
                    fontSize: 20,
                  ),
                ),
        );
      }),
    );
  }

  Widget _buildKeypadGrid() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['BACK', '0', 'CLEAR'],
    ];

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((key) {
              final isButton1 = key == '1';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                child: SizedBox(
                  width: 80,
                  height: 48,
                  child: TvFocusableCard(
                    focusNode: isButton1 ? _button1FocusNode : null,
                    autoFocus: isButton1,
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      if (key == 'BACK') {
                        _onBackspace();
                      } else if (key == 'CLEAR') {
                        _onClear();
                      } else {
                        _onNumTap(key);
                      }
                    },
                    child: Container(
                      color: key == 'BACK' || key == 'CLEAR'
                          ? const Color(0xFF282828)
                          : const Color(0xFF1F1F1F),
                      alignment: Alignment.center,
                      child: key == 'BACK'
                          ? const Icon(Icons.backspace_outlined,
                              color: Colors.white, size: 20)
                          : Text(
                              key,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: key.length > 1 ? 12 : 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

/// TV-optimized dialog to unlock with an existing 4-digit passcode.
class UnlockPasscodeDialog extends StatefulWidget {
  const UnlockPasscodeDialog({super.key});

  @override
  State<UnlockPasscodeDialog> createState() => _UnlockPasscodeDialogState();
}

class _UnlockPasscodeDialogState extends State<UnlockPasscodeDialog> {
  final FocusNode _button1FocusNode = FocusNode();
  String _pin = '';
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _button1FocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _button1FocusNode.dispose();
    super.dispose();
  }

  void _onNumTap(String num) {
    setState(() {
      _errorMessage = '';
      if (_pin.length < 4) {
        _pin += num;
        if (_pin.length == 4) {
          _verifyAndUnlock();
        }
      }
    });
  }

  void _onBackspace() {
    setState(() {
      _errorMessage = '';
      if (_pin.isNotEmpty) {
        _pin = _pin.substring(0, _pin.length - 1);
      }
    });
  }

  void _onClear() {
    setState(() {
      _errorMessage = '';
      _pin = '';
      _button1FocusNode.requestFocus();
    });
  }

  Future<void> _verifyAndUnlock() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('nsfw_passcode') ?? '';
    if (_pin == savedPin) {
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } else {
      setState(() {
        _errorMessage = 'Incorrect passcode. Please try again.';
        _pin = '';
      });
      _button1FocusNode.requestFocus();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
        _onNumTap('0');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
        _onNumTap('1');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
        _onNumTap('2');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
        _onNumTap('3');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
        _onNumTap('4');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
        _onNumTap('5');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
        _onNumTap('6');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
        _onNumTap('7');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
        _onNumTap('8');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
        _onNumTap('9');
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
        _onBackspace();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2C2C2C)),
        ),
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(24),
          child: FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_open_rounded,
                  color: Colors.redAccent.shade700,
                  size: 44,
                ),
                const SizedBox(height: 12),
                Text(
                  "Enter Passcode",
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Enter the 4-digit passcode to disable the NSFW Filter.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),

                // PIN indicator slots
                _buildPinDisplay(_pin),
                const SizedBox(height: 12),

                // Error state
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                // Keypad Grid
                _buildKeypadGrid(),

                const SizedBox(height: 16),
                // Cancel Action
                TvFocusableCard(
                  onTap: () => Navigator.of(context).pop(false),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    color: const Color(0xFF262626),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    child: Text(
                      "Cancel",
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14,
                      ),
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

  Widget _buildPinDisplay(String pin) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final isFilled = index < pin.length;
        final isCurrent = index == pin.length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 48,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isFilled
                  ? Colors.redAccent.shade700
                  : isCurrent
                      ? Colors.redAccent.withOpacity(0.5)
                      : const Color(0xFF333333),
              width: isFilled || isCurrent ? 2 : 1,
            ),
            boxShadow: isFilled
                ? [
                    BoxShadow(
                      color: Colors.redAccent.shade700.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: isFilled
              ? Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.shade700,
                    shape: BoxShape.circle,
                  ),
                )
              : Text(
                  "-",
                  style: GoogleFonts.outfit(
                    color: Colors.grey.shade600,
                    fontSize: 20,
                  ),
                ),
        );
      }),
    );
  }

  Widget _buildKeypadGrid() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['BACK', '0', 'CLEAR'],
    ];

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((key) {
              final isButton1 = key == '1';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                child: SizedBox(
                  width: 80,
                  height: 48,
                  child: TvFocusableCard(
                    focusNode: isButton1 ? _button1FocusNode : null,
                    autoFocus: isButton1,
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      if (key == 'BACK') {
                        _onBackspace();
                      } else if (key == 'CLEAR') {
                        _onClear();
                      } else {
                        _onNumTap(key);
                      }
                    },
                    child: Container(
                      color: key == 'BACK' || key == 'CLEAR'
                          ? const Color(0xFF282828)
                          : const Color(0xFF1F1F1F),
                      alignment: Alignment.center,
                      child: key == 'BACK'
                          ? const Icon(Icons.backspace_outlined,
                              color: Colors.white, size: 20)
                          : Text(
                              key,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: key.length > 1 ? 12 : 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}
