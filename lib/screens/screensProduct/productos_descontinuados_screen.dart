import 'dart:io';
import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';

class ProductosDescontinuadosScreen extends StatefulWidget {
  const ProductosDescontinuadosScreen({super.key});

  @override
  State<ProductosDescontinuadosScreen> createState() =>
      _ProductosDescontinuadosScreenState();
}

class _ProductosDescontinuadosScreenState
    extends State<ProductosDescontinuadosScreen> {
  late Future<List<Map<String, dynamic>>> _productosFuture;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _productosFuture = _obtenerDescontinuados();
  }

  Future<List<Map<String, dynamic>>> _obtenerDescontinuados() async {
    final filas = await DatabaseHelper.instance.getProductosConStockBatch();
    return filas.where((f) => (f['activo'] as int) == 0).toList();
  }

  Future<void> _refrescar() async {
    setState(() => _cargar());
    await _productosFuture;
  }

  Future<void> _reactivar(int id) async {
    await DatabaseHelper.instance.toggleActivoProducto(id, true);
    _refrescar();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Descontinuados',
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _productosFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final items = snapshot.data ?? [];

            if (items.isEmpty) {
              // Se mantiene dentro de un ListView para que el pull-to-refresh siga funcionando.
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 100),
                  EmptyState(
                    icono: Icons.inventory_2_outlined,
                    mensaje: 'No hay productos descontinuados',
                  ),
                ],
              );
            }

            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final p = items[index];
                final imagenPath = p['imagenPath'] as String?;

                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: imagenPath != null
                        ? Image.file(
                            File(imagenPath),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.inventory_2_outlined,
                                color: Colors.grey),
                          ),
                  ),
                  title: Text(
                    p['nombre'] as String,
                    style: AppText.cuerpo(size: 19, color: Colors.grey),
                  ),
                  subtitle: Text(
                    'Stock al descontinuar: ${(p['stockActual'] as num).toInt()} ${p['unidad']}',
                    style: AppText.cuerpo(size: 15, color: Colors.grey),
                  ),
                  trailing: TextButton(
                    onPressed: () => _reactivar(p['id'] as int),
                    child: Text(
                      'Reactivar',
                      style: AppText.cuerpo(color: AppColors.verde),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}