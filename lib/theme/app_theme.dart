import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colores, tipografía y medidas centrales de la app. Todas las
/// pantallas deben tomar sus valores de aquí en vez de declarar
/// colores o tamaños sueltos, para que un ajuste futuro (ej. cambiar
/// el verde corporativo) se haga en un solo lugar.
class AppColors {
  static const verde = Color.fromARGB(255, 3, 124, 88);
  static const verdeClaro = Color(0xFFE2F2ED);
  static const fondo = Colors.white;
  static const textoPrincipal = Colors.black;
  static const textoSecundario = Colors.black54;
  static const alerta = Color(0xFFC62828);
  static const advertencia = Color(0xFFE59500);
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class AppRadius {
  static const card = 14.0;
  static const campo = 10.0;
  static const boton = 12.0;
  static const sheet = 24.0;
}

/// Estilos de texto centrales. Los títulos de pantalla y de sección
/// usan ADLaMDisplay (la fuente "de marca"); el resto del contenido
/// usa Kreon. No mezclar otras fuentes sueltas en las pantallas.
class AppText {
  static TextStyle tituloPantalla({Color color = AppColors.textoPrincipal}) =>
      GoogleFonts.aDLaMDisplay(fontSize: 20, color: color);

  static TextStyle tituloSeccion({Color color = AppColors.textoPrincipal}) =>
      GoogleFonts.aDLaMDisplay(fontSize: 16, color: color);

  static TextStyle cuerpo({double size = 15, Color color = AppColors.textoPrincipal, FontWeight? peso}) =>
      GoogleFonts.kreon(fontSize: size, color: color, fontWeight: peso);

  static TextStyle secundario({double size = 13}) =>
      GoogleFonts.kreon(fontSize: size, color: AppColors.textoSecundario);
}