import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Scaffold estándar de la app: AppBar verde con título en la
/// tipografía de marca, fondo blanco. Úsalo en vez de armar un
/// Scaffold + AppBar manualmente en cada pantalla nueva.
class AppScaffold extends StatelessWidget {
  final String titulo;
  final List<Widget>? acciones;
  final PreferredSizeWidget? bottom;
  final Widget body;
  final Widget? floatingActionButton;

  const AppScaffold({
    super.key,
    required this.titulo,
    required this.body,
    this.acciones,
    this.bottom,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(titulo, style: AppText.tituloPantalla()),
        backgroundColor: AppColors.verde,
        actions: acciones,
        bottom: bottom,
      ),
      backgroundColor: AppColors.fondo,
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}