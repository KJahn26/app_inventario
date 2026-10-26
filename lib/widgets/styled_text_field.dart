import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType tipo;
  final String? helper;
  final bool enabled;
  final String? Function(String?)? validator;

  const StyledTextField({
    super.key,
    required this.controller,
    required this.label,
    this.tipo = TextInputType.text,
    this.helper,
    this.enabled = true,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: tipo,
      style: AppText.cuerpo(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppText.secundario(),
        helperText: helper,
        helperStyle: AppText.secundario(size: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.campo)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.campo),
          borderSide: const BorderSide(color: AppColors.verde, width: 2),
        ),
      ),
      validator: validator,
    );
  }
}