import 'package:flutter/material.dart';
import '../theme.dart';

class PulseChip extends StatelessWidget {
  final Widget label;
  final IconData? icon;
  final bool filled;
  final EdgeInsets padding;

  const PulseChip({
    super.key,
    required this.label,
    this.icon,
    this.filled = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled
        ? const Color.fromRGBO(255, 255, 255, 0.06)
        : Colors.transparent;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kLineColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14),
            const SizedBox(width: 6),
          ],
          DefaultTextStyle(
            style: const TextStyle(
              fontSize: 12,
              color: kFgColor,
              fontWeight: FontWeight.w600,
            ),
            child: label,
          ),
        ],
      ),
    );
  }
}
