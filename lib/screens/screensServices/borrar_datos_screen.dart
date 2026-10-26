import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/primary_button.dart';
import 'data_wipe_service.dart';
import '../home_screen.dart';

class BorrarDatosScreen extends StatefulWidget {
  const BorrarDatosScreen({super.key});

  @override
  State<BorrarDatosScreen> createState() => _BorrarDatosScreenState();
}

class _BorrarDatosScreenState extends State<BorrarDatosScreen> {
  bool _entendido = false;
  bool _procesando = false;

  Future<void> _ejecutar() async {
    setState(() => _procesando = true);

    final resultado = await DataWipeService.exportarYBorrarTodo();

    if (!mounted) return;
    setState(() => _procesando = false);

    if (resultado == ResultadoBorrado.exportacionNoCompletada) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          'No se completó la exportación. No se borró nada, tu información sigue intacta.',
          style: AppText.cuerpo(color: Colors.white),
        ), backgroundColor: AppColors.alerta),
      );
      return;
    }

    // Vuelve a Home limpiando toda la pila: las demás pantallas tienen
    // datos en memoria que ya no son válidos tras el borrado.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Borrar todos los datos',
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.alerta.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.alerta.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.alerta),
                    SizedBox(width: AppSpacing.sm),
                    Text('Esta acción es irreversible', style: AppText.tituloSeccion(color: AppColors.alerta)),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Se eliminarán todos los productos, lotes, movimientos y conteos físicos. '
                    'Antes de borrar, se te pedirá exportar un respaldo completo (Excel) — '
                    'si no lo guardas, el borrado se cancela automáticamente.',
                    style: AppText.cuerpo(size: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            CheckboxListTile(
              value: _entendido,
              onChanged: (v) => setState(() => _entendido = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text('Entiendo que esto borrará toda la información del negocio', style: AppText.cuerpo(size: 14)),
            ),
            const Spacer(),
            PrimaryButton(
              texto: 'Exportar y borrar todo',
              color: AppColors.advertencia,
              cargando: _procesando,
              onPressed: _entendido ? _ejecutar : null,
            ),
          ],
        ),
      ),
    );
  }
}