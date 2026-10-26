import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';
import 'screens/screensServices/notificacion_service.dart';
import 'screens/screensServices/reposicion_check_service.dart';

void main() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  WidgetsFlutterBinding.ensureInitialized();
  await NotificacionService.instance.inicializar();

  ReposicionCheckService.verificarCatalogoCompleto(); // revisar stock bajo al abrir la app
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventario',
      home: const HomeScreen(),
    );
  }
}
