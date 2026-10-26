import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';

class MercanciaBajaRotacionScreen extends StatefulWidget {
  const MercanciaBajaRotacionScreen({super.key});

  @override
  State<MercanciaBajaRotacionScreen> createState() => _MercanciaBajaRotacionScreenState();
}

class _MercanciaBajaRotacionScreenState extends State<MercanciaBajaRotacionScreen> {
  late Future<List<Map<String, dynamic>>> _productosFuture;

  @override
  void initState() {
    super.initState();
    _productosFuture = DatabaseHelper.instance.getMercanciaBajaRotacion(dias: 90);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Baja rotación',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _productosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data ?? [];

          if (items.isEmpty) {
            return const EmptyState(
              icono: Icons.savings_outlined,
              mensaje: 'No hay mercancía inmovilizada por más de 90 días.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = items[index];
              final valor = (p['valorInmovilizado'] as num).toDouble();
              final stock = (p['stockActual'] as num).toInt();

              return ListTile(
                leading: const Icon(Icons.savings_outlined, color: Colors.green),
                title: Text(p['nombre'] as String, style: AppText.cuerpo(size: 18)),
                subtitle: Text('$stock ${p['unidad']} en stock', style: AppText.cuerpo()),
                trailing: Text(
                  '${valor.toStringAsFixed(0)} Q',
                  style: AppText.cuerpo(size: 16, peso: FontWeight.bold),
                ),
              );
            },
          );
        },
      ),
    );
  }
}