import 'package:flutter/material.dart';

class TvFocusableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleFactor;
  final BorderRadius borderRadius;
  final FocusNode? focusNode;
  final bool autoFocus;

  const TvFocusableCard({
    super.key,
    required this.child,
    required this.onTap,
    this.scaleFactor = 1.06,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.focusNode,
    this.autoFocus = false,
  });

  @override
  State<TvFocusableCard> createState() => _TvFocusableCardState();
}

class _TvFocusableCardState extends State<TvFocusableCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      focusNode: widget.focusNode,
      autofocus: widget.autoFocus,
      onFocusChange: (hasFocus) {
        setState(() {
          _isFocused = hasFocus;
        });
      },
      onTap: widget.onTap,
      borderRadius: widget.borderRadius,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      splashColor: Colors.red.withOpacity(0.3),
      highlightColor: Colors.transparent,
      child: AnimatedScale(
        scale: _isFocused ? widget.scaleFactor : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: _isFocused ? Colors.redAccent.shade700 : Colors.transparent,
              width: 3.0,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.redAccent.shade700.withOpacity(0.45),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
