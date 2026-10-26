import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';

class PrecioBajoCostoScreen extends StatefulWidget {
  const PrecioBajoCostoScreen({super.key});

  @override
  State<PrecioBajoCostoScreen> createState() => _PrecioBajoCostoScreenState();
}

class _PrecioBajoCostoScreenState extends State<PrecioBajoCostoScreen> {
  late Future<List<Map<String, dynamic>>> _productosFuture;

  @override
  void initState() {
    super.initState();
    _productosFuture = DatabaseHelper.instance.getProductosPrecioBajoCosto();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Precio bajo costo',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _productosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data ?? [];

          if (items.isEmpty) {
            return const EmptyState(
              icono: Icons.trending_down,
              mensaje: 'Ningún producto se vende por debajo del costo.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = items[index];
              final precio = (p['precioReferencia'] as num).toDouble();
              final costo = (p['costoReferencia'] as num).toDouble();
              final diferenciaPct = ((precio - costo) / costo * 100);

              return ListTile(
                title: Text(p['nombre'] as String, style: AppText.cuerpo(size: 18)),
                subtitle: Text(
                  'Venta: ${precio.toStringAsFixed(0)} Q ·   Costo: ${costo.toStringAsFixed(0)} Q',
                  style: AppText.cuerpo(),
                ),
                trailing: Text(
                  '${diferenciaPct.toStringAsFixed(0)}%',
                  style: AppText.cuerpo(
                    size: 16,
                    color: Colors.red,
                    peso: FontWeight.bold,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}