import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/producto.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/styled_text_field.dart';

class AgregarEntradaScreen extends StatefulWidget {
  const AgregarEntradaScreen({super.key});

  @override
  State<AgregarEntradaScreen> createState() => _AgregarEntradaScreenState();
}

class _AgregarEntradaScreenState extends State<AgregarEntradaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadController = TextEditingController();
  final _costoController = TextEditingController();

  List<Producto> _productos = [];
  Producto? _productoSeleccionado;
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarProductos();
  }

  Future<void> _cargarProductos() async {
    final productos = await DatabaseHelper.instance.getProductos();
    setState(() {
      _productos = productos;
      _cargando = false;
    });
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _costoController.dispose();
    super.dispose();
  }

  Future<void> _guardarEntrada() async {
    if (_productoSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un producto')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    await DatabaseHelper.instance.registrarEntrada(
      productoId: _productoSeleccionado!.id!,
      cantidad: int.parse(_cantidadController.text.trim()),
      costoUnitario: double.parse(_costoController.text.trim()),
    );

    if (!mounted) return;

    setState(() => _guardando = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Entrada registrada para ${_productoSeleccionado!.nombre}'),
      ),
    );

    _cantidadController.clear();
    _costoController.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const AppScaffold(
        titulo: 'Agregar entrada de stock',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_productos.isEmpty) {
      return const AppScaffold(
        titulo: 'Agregar entrada de stock',
        body: EmptyState(
          icono: Icons.inventory_2_outlined,
          mensaje: 'Primero registra al menos un producto',
        ),
      );
    }

    return AppScaffold(
      titulo: 'Agregar entrada de stock',
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
                onChanged: (value) {
                  setState(() => _productoSeleccionado = value);
                },
              ),
              const SizedBox(height: 16),
              StyledTextField(
                controller: _cantidadController,
                label: 'Cantidad que ingresa',
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
                controller: _costoController,
                label: 'Costo unitario de compra',
                tipo: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa un costo';
                  }
                  final n = double.tryParse(value.trim());
                  if (n == null || n <= 0) {
                    return 'Debe ser un número mayor a 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                texto: 'Registrar entrada',
                cargando: _guardando,
                onPressed: _guardarEntrada,
              ),
            ],
          ),
        ),
      ),
    );
  }
}