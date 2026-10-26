import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class EmptyState extends StatelessWidget {
  final IconData icono;
  final String mensaje;

  const EmptyState({super.key, this.icono = Icons.inbox_outlined, required this.mensaje});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: AppSpacing.md),
            Text(mensaje, textAlign: TextAlign.center, style: AppText.secundario(size: 14)),
          ],
        ),
      ),
    );
  }
}