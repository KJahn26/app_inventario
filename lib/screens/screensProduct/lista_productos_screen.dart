import 'dart:io';
import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/producto.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/menu_acciones_sheet.dart';
import 'agregar_producto_screen.dart';
import 'agregar_entrada_screen.dart';
import 'registrar_venta_screen.dart';
import 'productos_descontinuados_screen.dart';
import 'registrar_conteo_screen.dart';
import 'editar_producto_screen.dart';

class ListaProductosScreen extends StatefulWidget {
  const ListaProductosScreen({super.key});

  @override
  State<ListaProductosScreen> createState() => _ListaProductosScreenState();
}

class _ListaProductosScreenState extends State<ListaProductosScreen> {
  late Future<List<_ProductoConStock>> _productosFuture;

  @override
  void initState() {
    super.initState();
    _cargarProductos();
  }

  void _cargarProductos() {
    _productosFuture = _obtenerProductosActivosConStock();
  }

  Future<List<_ProductoConStock>> _obtenerProductosActivosConStock() async {
    final filas = await DatabaseHelper.instance.getProductosConStockBatch();
    return filas
        .where((fila) => (fila['activo'] as int) == 1)
        .map((fila) => _ProductoConStock(
              producto: Producto.fromMap(fila),
              stockActual: (fila['stockActual'] as num).toInt(),
            ))
        .toList();
  }

  Future<void> _refrescar() async {
    setState(() => _cargarProductos());
    await _productosFuture;
  }

  Future<void> _irAAgregarProducto() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AgregarProductoScreen()),
    );
    _refrescar();
  }

  Future<void> _irARegistrarVenta() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegistrarVentaScreen()),
    );
    _refrescar();
  }

  Future<void> _irAAgregarEntrada() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AgregarEntradaScreen()),
    );
    _refrescar();
  }

  Future<void> _irARegistrarConteo() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegistrarConteoScreen()),
    );
    _refrescar();
  }

  Future<void> _editarProducto(Producto producto) async {
    final cambio = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditarProductoScreen(producto: producto)),
    );
    if (cambio == true) _refrescar();
  }

  Future<void> _descontinuar(int id) async {
    await DatabaseHelper.instance.toggleActivoProducto(id, false);
    _refrescar();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Productos',
      acciones: [
        IconButton(
          icon: Icon(Icons.point_of_sale),
          color: Colors.black,
          iconSize: 32,
          tooltip: 'Registrar venta',
          onPressed: _irARegistrarVenta
        ),
        
      ],
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<_ProductoConStock>>(
          future: _productosFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final items = snapshot.data ?? [];

            if (items.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 60),
                  EmptyState(
                    icono: Icons.inventory_2_outlined,
                    mensaje: 'No hay productos activos aún.\nAgrega el primero con el botón de abajo.',
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                final bajoMinimo = item.stockActual < item.producto.stockMinimo;

                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.campo),
                    child: item.producto.imagenPath != null
                        ? Image.file(
                            File(item.producto.imagenPath!),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.inventory_2_outlined, color: Colors.grey),
                          ),
                  ),
                  title: Text(item.producto.nombre, style: AppText.cuerpo(size: 19)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stock: ${item.stockActual} ${item.producto.unidad} (mínimo: ${item.producto.stockMinimo})',
                        style: AppText.cuerpo(size: 15),
                      ),
                      if (item.producto.precioVentaSugerido != null)
                        Text(
                          'Precio sugerido: \$${item.producto.precioVentaSugerido!.toStringAsFixed(0)}',
                          style: AppText.cuerpo(size: 13, color: AppColors.verde, peso: FontWeight.w600),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (bajoMinimo)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.warning_amber_rounded, color: AppColors.alerta),
                        ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'editar') {
                            _editarProducto(item.producto);
                          } else if (value == 'descontinuar') {
                            _descontinuar(item.producto.id!);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'editar',
                            child: Row(children: [
                              const Icon(Icons.edit_outlined, size: 18, color: Colors.black54),
                              const SizedBox(width: AppSpacing.sm),
                              Text('Editar', style: AppText.cuerpo()),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'descontinuar',
                            child: Row(children: [
                              const Icon(Icons.archive_outlined, size: 18, color: Colors.black54),
                              const SizedBox(width: AppSpacing.sm),
                              Text('Descontinuar', style: AppText.cuerpo()),
                            ]),
                          ),
                        ],
                      ),
                    ],
                  ),
                  tileColor: bajoMinimo ? AppColors.alerta.withValues(alpha: 0.05) : null,
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: 
          FloatingActionButton.extended(
            onPressed: () => mostrarMenuAcciones(
              context,
              titulo: 'Acciones de productos',
              acciones: [
                AccionMenu(
                  icono: Icons.add_box_outlined,
                  titulo: 'Agregar producto',
                  subtitulo: 'Crea un nuevo producto en el inventario',
                  onTap: _irAAgregarProducto,
                ),
                AccionMenu(
                  icono: Icons.add_shopping_cart,
                  titulo: 'Agregar entrada de stock',
                  subtitulo: 'Registra una compra o reposición',
                  onTap: _irAAgregarEntrada,
                ),
                AccionMenu(
                  icono: Icons.fact_check_outlined,
                  color: Colors.blue,
                  titulo: 'Conteo físico',
                  subtitulo: 'Compara el stock contado contra el sistema',
                  onTap: _irARegistrarConteo,
                ),
                AccionMenu(
                  icono: Icons.archive_outlined,
                  color: Colors.grey.shade700,
                  titulo: 'Productos descontinuados',
                  subtitulo: 'Ver y reactivar productos dados de baja',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProductosDescontinuadosScreen()),
                    );
                    _refrescar();
                  },
                ),
              ],
            ),
            icon: Icon(Icons.menu),
            label: Text('Más opciones', style: AppText.cuerpo(size: 16, color: Colors.white)),
            backgroundColor:  Color.fromARGB(255, 3, 124, 88),
            foregroundColor: Colors.white,
      ),
    );
  }
}

class _ProductoConStock {
  final Producto producto;
  final int stockActual;

  _ProductoConStock({required this.producto, required this.stockActual});
}