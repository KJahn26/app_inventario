import 'dart:io';
import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/producto.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/styled_text_field.dart';
import '../screensServices/imagen_service.dart';

class EditarProductoScreen extends StatefulWidget {
  final Producto producto;
  const EditarProductoScreen({super.key, required this.producto});

  @override
  State<EditarProductoScreen> createState() => _EditarProductoScreenState();
}

class _EditarProductoScreenState extends State<EditarProductoScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _unidadController;
  late final TextEditingController _stockMinimoController;
  late final TextEditingController _precioSugeridoController;

  String? _imagenPath;
  late final String? _imagenPathOriginal;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final p = widget.producto;
    _nombreController = TextEditingController(text: p.nombre);
    _unidadController = TextEditingController(text: p.unidad);
    _stockMinimoController = TextEditingController(text: p.stockMinimo.toString());
    _precioSugeridoController = TextEditingController(
      text: p.precioVentaSugerido?.toStringAsFixed(0) ?? '',
    );
    _imagenPath = p.imagenPath;
    _imagenPathOriginal = p.imagenPath;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _unidadController.dispose();
    _stockMinimoController.dispose();
    _precioSugeridoController.dispose();
    super.dispose();
  }

  Future<void> _elegirImagen() async {
    final ruta = await ImagenService.seleccionarYGuardarImagen();
    if (ruta != null) setState(() => _imagenPath = ruta);
  }

  void _quitarImagen() {
    setState(() => _imagenPath = null);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final actualizado = Producto(
      id: widget.producto.id,
      nombre: _nombreController.text.trim(),
      unidad: _unidadController.text.trim(),
      stockMinimo: int.parse(_stockMinimoController.text.trim()),
      activo: widget.producto.activo,
      imagenPath: _imagenPath,
      precioVentaSugerido: _precioSugeridoController.text.trim().isEmpty
          ? null
          : double.tryParse(_precioSugeridoController.text.trim()),
    );

    await DatabaseHelper.instance.actualizarProducto(actualizado);

    // Si se reemplazó la foto, borra la anterior para no dejar archivos huérfanos.
    if (_imagenPathOriginal != null && _imagenPathOriginal != _imagenPath) {
      await ImagenService.eliminarImagen(_imagenPathOriginal);
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Editar producto',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            Center(
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: _elegirImagen,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                        image: _imagenPath != null
                            ? DecorationImage(
                                image: FileImage(
                                  File(_imagenPath!)
                                ),
                                fit: BoxFit.scaleDown,
                              )
                            : null,
                      ),
                      child:_imagenPath==null 
                        ? Icon(
                          Icons.add_a_photo_outlined,
                         size: 36, 
                         color: Colors.grey.shade600)
                         : null,
                    
                    ),
                  ),
                  if (_imagenPath != null)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _quitarImagen,
                        child: Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.alerta, 
                            shape: BoxShape.circle),
                          child: Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
              ],
            ),
          ),
            const SizedBox(height: 28),
            StyledTextField(
              controller: _nombreController,
              label: 'Nombre del producto',
              validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa un nombre' : null,
            ),
            const SizedBox(height: 16),
            StyledTextField(
              controller: _unidadController,
              label: 'Unidad (ej: unidad, kg, litro)',
              validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa una unidad' : null,
            ),
            const SizedBox(height: 16),
            StyledTextField(
              controller: _stockMinimoController,
              label: 'Stock mínimo',
              tipo: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresa un número';
                if (int.tryParse(v.trim()) == null) return 'Debe ser un número entero';
                return null;
              },
            ),
            const SizedBox(height: 16),
            StyledTextField(
              controller: _precioSugeridoController,
              label: 'Precio de venta sugerido (opcional)',
              tipo: const TextInputType.numberWithOptions(decimal: true),
              helper: 'Aparecerá precargado al registrar una venta',
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                if (double.tryParse(v.trim()) == null) return 'Debe ser un número válido';
                return null;
              },
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              texto: 'Guardar cambios',
              cargando: _guardando,
              onPressed: _guardar,
            ),
          ],
        ),
      ),
    );
  }
}