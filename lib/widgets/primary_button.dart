import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PrimaryButton extends StatelessWidget {
  final String texto;
  final VoidCallback? onPressed;
  final bool cargando;
  final Color color;

  const PrimaryButton({
    super.key, 
    required this.texto, 
    required this.onPressed, 
    this.cargando = false,
    this.color = AppColors.verde,});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: cargando ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.boton)),
      ),
      child: cargando
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(texto, style: AppText.tituloSeccion(color: Colors.white)),
    );
  }
}