import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';

class SinVentasRecientesScreen extends StatefulWidget {
  const SinVentasRecientesScreen({super.key});

  @override
  State<SinVentasRecientesScreen> createState() => _SinVentasRecientesScreenState();
}

class _SinVentasRecientesScreenState extends State<SinVentasRecientesScreen> {
  late Future<List<Map<String, dynamic>>> _productosFuture;

  @override
  void initState() {
    super.initState();
    _productosFuture = DatabaseHelper.instance.getProductosSinVentasRecientes(dias: 30);
  }

  String _diasDesde(String? fechaIso) {
    if (fechaIso == null) return 'Sin ventas registradas';
    final dias = DateTime.now().difference(DateTime.parse(fechaIso)).inDays;
    return 'Última venta: hace $dias días';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Sin ventas recientes',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _productosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data ?? [];

          if (items.isEmpty) {
            return const EmptyState(
              icono: Icons.inventory_outlined,
              mensaje: 'Todos los productos activos tuvieron ventas en los últimos 30 días.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = items[index];
              return ListTile(
                leading: const Icon(Icons.inventory_outlined, color: Colors.orange),
                title: Text(p['nombre'] as String, style: AppText.cuerpo(size: 18)),
                subtitle: Text(_diasDesde(p['ultimaVenta'] as String?), style: AppText.cuerpo()),
              );
            },
          );
        },
      ),
    );
  }
}