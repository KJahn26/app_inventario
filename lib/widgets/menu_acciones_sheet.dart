import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _verde = Color.fromARGB(255, 3, 124, 88);

class AccionMenu {
  final IconData icono;
  final Color color;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  AccionMenu({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
    this.color = _verde,
  });
}

/// Muestra un panel inferior con un listado de acciones (ícono +
/// título + descripción corta), usado para agrupar acciones
/// secundarias sin saturar el AppBar o apilar múltiples FAB.
Future<void> mostrarMenuAcciones(
  BuildContext context, {
  required String titulo,
  required List<AccionMenu> acciones,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(titulo, style: GoogleFonts.aDLaMDisplay(fontSize: 18, color: Colors.black)),
              const SizedBox(height: 8),
              ...acciones.map((a) => _FilaAccion(accion: a)),
            ],
          ),
        ),
      );
    },
  );
}

class _FilaAccion extends StatelessWidget {
  final AccionMenu accion;
  const _FilaAccion({required this.accion});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.pop(context);
        accion.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accion.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(accion.icono, color: accion.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(accion.titulo,
                      style: GoogleFonts.kreon(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                  const SizedBox(height: 2),
                  Text(accion.subtitulo, style: GoogleFonts.kreon(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black26),
          ],
        ),
      ),
    );
  }
}