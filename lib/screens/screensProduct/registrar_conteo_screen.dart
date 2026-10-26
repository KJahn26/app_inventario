import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/producto.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/styled_text_field.dart';

class RegistrarConteoScreen extends StatefulWidget {
  const RegistrarConteoScreen({super.key});

  @override
  State<RegistrarConteoScreen> createState() => _RegistrarConteoScreenState();
}

class _RegistrarConteoScreenState extends State<RegistrarConteoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadController = TextEditingController();

  List<Producto> _productos = [];
  Producto? _productoSeleccionado;
  int? _stockSistema;
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
      _productos = productos.where((p) => p.activo).toList();
      _cargando = false;
    });
  }

  Future<void> _seleccionarProducto(Producto? producto) async {
    setState(() {
      _productoSeleccionado = producto;
      _stockSistema = null;
    });
    if (producto != null) {
      final stock = await DatabaseHelper.instance.getStockActual(producto.id!);
      setState(() => _stockSistema = stock);
    }
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    super.dispose();
  }

  Future<void> _guardarConteo() async {
    if (_productoSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selecciona un producto', style: AppText.cuerpo())),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final cantidadContada = int.parse(_cantidadController.text.trim());
    await DatabaseHelper.instance.registrarConteoFisico(
      productoId: _productoSeleccionado!.id!,
      cantidadContada: cantidadContada,
    );

    final diferencia = cantidadContada - (_stockSistema ?? 0);

    if (!mounted) return;
    setState(() => _guardando = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          diferencia == 0
              ? 'Conteo registrado: sin diferencias'
              : 'Conteo registrado: diferencia de $diferencia unidades',
          style: AppText.cuerpo(),
        ),
      ),
    );

    _cantidadController.clear();
    setState(() {
      _productoSeleccionado = null;
      _stockSistema = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const AppScaffold(
        titulo: 'Conteo físico',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return AppScaffold(
      titulo: 'Conteo físico',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.verde.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.verde.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline, color: AppColors.advertencia),
                    SizedBox(width: AppSpacing.sm),
                    Text('Importante',
                     style: AppText.tituloSeccion(
                      color: AppColors.advertencia
                      )
                      ),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Esta pantalla sirve para comparar la cantidad real encontrada '
                    'en el inventario con la cantidad registrada en el sistema y detectar posibles diferencias.\n\n'
                    'Al registrar un conteo, el stock actual no se ajusta ni se corrige automáticamente. '
                    'Si existe una diferencia, esta quedará registrada para su revisión '
                    'en el apartado de oportunidades. \n\n'
                    'Si no se le informa es porque no existe desajuste',
                    style: AppText.cuerpo(size: 14),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Form(
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
              if (_stockSistema != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Stock registrado en el sistema: $_stockSistema ${_productoSeleccionado?.unidad ?? ''}',
                  style: AppText.cuerpo(peso: FontWeight.bold),
                ),
              ],
              const SizedBox(height: 16),
              StyledTextField(
                controller: _cantidadController,
                label: 'Cantidad contada físicamente',
                tipo: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Ingresa una cantidad';
                  if (int.tryParse(value.trim()) == null) return 'Debe ser un número entero';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                texto: 'Registrar conteo',
                cargando: _guardando,
                onPressed: _guardarConteo,
              ),
            ],
          ),
        ),





          ]

        )
      ),
    );
  }
}