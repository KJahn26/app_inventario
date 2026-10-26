import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/producto.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/styled_text_field.dart';
import '../screensServices/notificacion_service.dart';
import '../screensServices/reposicion_check_service.dart';

class RegistrarVentaScreen extends StatefulWidget {
  const RegistrarVentaScreen({super.key});

  @override
  State<RegistrarVentaScreen> createState() => _RegistrarVentaScreenState();
}

class _RegistrarVentaScreenState extends State<RegistrarVentaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadController = TextEditingController();
  final _precioController = TextEditingController();

  List<Producto> _productos = [];
  Producto? _productoSeleccionado;
  int _stockActual = 0;
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarProductos();
    _cantidadController.addListener(_actualizarTotal);
    _precioController.addListener(_actualizarTotal);
  }

  void _actualizarTotal() => setState(() {});

  double get _totalVenta {
    final cantidad = int.tryParse(_cantidadController.text.trim()) ?? 0;
    final precio = double.tryParse(_precioController.text.trim()) ?? 0;
    return cantidad * precio;
  }

  Future<void> _cargarProductos() async {
    final productos = await DatabaseHelper.instance.getProductos();
    setState(() {
      _productos = productos;
      _cargando = false;
    });
  }

  Future<void> _seleccionarProducto(Producto? producto) async {
    setState(() => _productoSeleccionado = producto);
    if (producto != null) {
      final stock = await DatabaseHelper.instance.getStockActual(producto.id!);
      setState(() => _stockActual = stock);

      // Autocompleta con el precio sugerido, el usuario lo puede corregir.
      if (producto.precioVentaSugerido != null) {
        _precioController.text = producto.precioVentaSugerido!.toStringAsFixed(0);
      } else {
        _precioController.clear();
      }
    }
  }

  @override
  void dispose() {
    _cantidadController.removeListener(_actualizarTotal);
    _precioController.removeListener(_actualizarTotal);
    _cantidadController.dispose();
    _precioController.dispose();
    super.dispose();
  }

  Future<void> _guardarVenta() async {
    if (_productoSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un producto')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final exito = await DatabaseHelper.instance.registrarVentaPEPS(
      productoId: _productoSeleccionado!.id!,
      cantidadVendida: int.parse(_cantidadController.text.trim()),
      precioVenta: double.parse(_precioController.text.trim()),
    );

    if (!mounted) return;

    setState(() => _guardando = false);

    if (!exito) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay stock suficiente para esa venta')),
      );
      return;
    }

    final nuevoStock = await DatabaseHelper.instance
        .getStockActual(_productoSeleccionado!.id!);
    setState(() => _stockActual = nuevoStock);

    ReposicionCheckService.verificarProducto(_productoSeleccionado!.id!);
    if (nuevoStock < _productoSeleccionado!.stockMinimo) {
      await NotificacionService.instance.mostrarAlertaStockBajo(
        productoId: _productoSeleccionado!.id!,
        nombreProducto: _productoSeleccionado!.nombre,
        stockActual: nuevoStock,
        unidad: _productoSeleccionado!.unidad,
      );
    }

    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Venta registrada de ${_productoSeleccionado!.nombre}')),
    );

    _cantidadController.clear();
    _precioController.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const AppScaffold(
        titulo: 'Registrar venta',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_productos.isEmpty) {
      return const AppScaffold(
        titulo: 'Registrar venta',
        body: EmptyState(
          icono: Icons.inventory_2_outlined,
          mensaje: 'Primero registra al menos un producto',
        ),
      );
    }

    return AppScaffold(
      titulo: 'Registrar venta',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<Producto>(
                initialValue: _productoSeleccionado,
                decoration: InputDecoration(
                  labelText: 'Producto',
                  border: const OutlineInputBorder(),
                  labelStyle: AppText.cuerpo(),
                ),
                items: _productos.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Text('${p.nombre} (${p.unidad})', style: AppText.cuerpo()),
                  );
                }).toList(),
                onChanged: _seleccionarProducto,
              ),
              if (_productoSeleccionado != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Stock actual: $_stockActual ${_productoSeleccionado!.unidad}',
                  style: AppText.cuerpo(
                    color: _stockActual < _productoSeleccionado!.stockMinimo
                        ? Colors.red
                        : Colors.black87,
                    peso: FontWeight.bold,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              StyledTextField(
                controller: _cantidadController,
                label: 'Cantidad vendida',
                tipo: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa una cantidad';
                  }
                  final n = int.tryParse(value.trim());
                  if (n == null || n <= 0) {
                    return 'Debe ser un número mayor a 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              StyledTextField(
                controller: _precioController,
                label: 'Precio de venta unitario',
                tipo: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa un precio';
                  }
                  final n = double.tryParse(value.trim());
                  if (n == null || n <= 0) {
                    return 'Debe ser un número mayor a 0';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),
              if (_totalVenta > 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.verdeClaro,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total de la venta', style: AppText.cuerpo(size: 14, color: AppColors.textoSecundario)),
                      Text('${_totalVenta.toStringAsFixed(0)} Q', style: AppText.tituloSeccion(color: AppColors.verde)),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              PrimaryButton(
                texto: 'Registrar venta',
                cargando: _guardando,
                onPressed: _guardarVenta,
              ),
            ],
          ),
        ),
      ),
    );
  }
}