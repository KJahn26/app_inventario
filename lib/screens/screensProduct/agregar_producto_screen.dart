import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../db/database_helper.dart';
import '../../models/producto.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/styled_text_field.dart';
import '../screensServices/imagen_service.dart';

class AgregarProductoScreen extends StatefulWidget {
  const AgregarProductoScreen({super.key});

  @override
  State<AgregarProductoScreen> createState() => _AgregarProductoScreenState();
}

class _AgregarProductoScreenState extends State<AgregarProductoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _unidadController = TextEditingController();
  final _stockMinimoController = TextEditingController();
  final _precioSugeridoController = TextEditingController();

  String? _imagenPath;
  bool _guardando = false;

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
    if (ruta != null) {
      setState(() => _imagenPath = ruta);
    }
  }

  Future<void> _quitarImagen() async {
    if (_imagenPath != null) {
      await ImagenService.eliminarImagen(
        _imagenPath,
      ); // borra el archivo huérfano recién copiado
    }
    setState(() => _imagenPath = null);
  }

  Future<void> _guardarProducto() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final producto = Producto(
      nombre: _nombreController.text.trim(),
      unidad: _unidadController.text.trim(),
      stockMinimo: int.parse(_stockMinimoController.text.trim()),
      imagenPath: _imagenPath,
      precioVentaSugerido: _precioSugeridoController.text.trim().isEmpty
          ? null
          : double.tryParse(_precioSugeridoController.text.trim()),
    );

    await DatabaseHelper.instance.insertProducto(producto);

    if (!mounted) return;

    setState(() => _guardando = false);

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${producto.nombre} guardado')));

    // Limpia el formulario para agregar otro producto seguido
    _nombreController.clear();
    _unidadController.clear();
    _stockMinimoController.clear();
    _precioSugeridoController.clear();
    setState(() => _imagenPath = null);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Agregar producto',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                  image: FileImage(File(_imagenPath!)),
                                  fit: BoxFit.scaleDown,
                                )
                              : null,
                        ),
                        child: _imagenPath == null
                            ? Icon(
                                Icons.add_a_photo_outlined,
                                size: 36,
                                color: Colors.grey,
                              )
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
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              StyledTextField(
                controller: _nombreController,
                label: 'Nombre del producto',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa un nombre';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              StyledTextField(
                controller: _unidadController,
                label: 'Unidad (ej: unidad, kg, litro)',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa una unidad';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              StyledTextField(
                controller: _stockMinimoController,
                label: 'Stock mínimo',
                tipo: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa un número';
                  }
                  if (int.tryParse(value.trim()) == null) {
                    return 'Debe ser un número entero';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              StyledTextField(
                controller: _precioSugeridoController,
                label: 'Precio de venta sugerido (opcional)',
                tipo: const TextInputType.numberWithOptions(decimal: true),
                helper: 'Se usa para detectar ventas por debajo del costo',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return null; // opcional
                  }
                  if (double.tryParse(value.trim()) == null) {
                    return 'Debe ser un número válido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                texto: 'Guardar producto',
                cargando: _guardando,
                onPressed: _guardarProducto,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
