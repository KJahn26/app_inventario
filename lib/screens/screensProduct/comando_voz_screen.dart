import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/styled_text_field.dart';
import '../../widgets/empty_state.dart';
import '../../db/database_helper.dart';
import '../../models/producto.dart';
import '../screensServices/voice_command_service.dart';
import '../screensServices/voice_parser_service.dart';

class ComandoVozScreen extends StatefulWidget {
  const ComandoVozScreen({super.key});

  @override
  State<ComandoVozScreen> createState() => _ComandoVozScreenState();
}

class _ComandoVozScreenState extends State<ComandoVozScreen> {
  bool _inicializando = true;
  bool _disponible = false;
  bool _escuchando = false;
  String _textoReconocido = '';

  ComandoVoz? _comando;
  Producto? _producto;
  List<Producto> _productosActivos = [];
  String? _resultadoConsulta;
  bool _guardando = false;

  final _cantidadController = TextEditingController();
  final _precioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    final productos = await DatabaseHelper.instance.getProductos();
    _productosActivos = productos.where((p) => p.activo).toList();
    final ok = await VoiceCommandService.inicializar();
    setState(() {
      _disponible = ok;
      _inicializando = false;
    });
  }

  @override
  void dispose() {
    VoiceCommandService.cancelar();
    _cantidadController.dispose();
    _precioController.dispose();
    super.dispose();
  }

  Future<void> _alternarEscucha() async {
    if (_escuchando) {
      await VoiceCommandService.detener();
      setState(() => _escuchando = false);
      _procesarComando();
      return;
    }

    setState(() {
      _textoReconocido = '';
      _comando = null;
      _producto = null;
      _resultadoConsulta = null;
      _escuchando = true;
    });

    await VoiceCommandService.escuchar(
      onResultado: (texto, esFinal) {
        setState(() => _textoReconocido = texto);
        if (esFinal) {
          setState(() => _escuchando = false);
          _procesarComando();
        }
      },
    );
  }

  void _procesarComando() {
    if (_textoReconocido.trim().isEmpty) return;

    final comando = VoiceParserService.interpretar(_textoReconocido);
    Producto? producto;

    if (comando.tipo != TipoComandoVoz.desconocido) {
      producto = VoiceParserService.encontrarProductoMasParecido(comando.nombreProductoDicho, _productosActivos);
    }

    setState(() {
      _comando = comando;
      _producto = producto;
      _cantidadController.text = comando.cantidad?.toString() ?? '';
      _precioController.text =
          comando.precio?.toStringAsFixed(0) ?? producto?.precioVentaSugerido?.toStringAsFixed(0) ?? '';
    });

    if (comando.tipo == TipoComandoVoz.consultaStock) {
      if (producto != null) {
        _consultarStock(producto);
      }else{
        setState(() {
          _resultadoConsulta = 'No encontré un producto parecido a "${comando.nombreProductoDicho}".';
        });
      }
    }
  }

  Future<void> _consultarStock(Producto producto) async {
    final stock = await DatabaseHelper.instance.getStockActual(producto.id!);
    setState(() => _resultadoConsulta = '${producto.nombre}: $stock ${producto.unidad} disponibles.');
  }

  Future<void> _confirmar() async {
    final comando = _comando;
    final producto = _producto;
    if (comando == null || producto == null) return;

    final cantidad = int.tryParse(_cantidadController.text.trim());
    final precio = double.tryParse(_precioController.text.trim());

    if (cantidad == null || cantidad <= 0) {
      _mostrarAviso('Ingresa una cantidad válida');
      return;
    }
    if (precio == null || precio <= 0) {
      _mostrarAviso(comando.tipo == TipoComandoVoz.venta ? 'Ingresa un precio válido' : 'Ingresa un costo válido');
      return;
    }

    setState(() => _guardando = true);
    final db = DatabaseHelper.instance;

    if (comando.tipo == TipoComandoVoz.venta) {
      final exito = await db.registrarVentaPEPS(
        productoId: producto.id!,
        cantidadVendida: cantidad,
        precioVenta: precio,
      );
      setState(() => _guardando = false);
      if (!exito) {
        _mostrarAviso('No hay stock suficiente para esa venta');
        return;
      }
    } else {
      await db.registrarEntrada(productoId: producto.id!, cantidad: cantidad, costoUnitario: precio);
      setState(() => _guardando = false);
    }

    if (!mounted) return;
    _mostrarAviso('${comando.tipo == TipoComandoVoz.venta ? 'Venta' : 'Entrada'} registrada');
    setState(() {
      _comando = null;
      _producto = null;
      _textoReconocido = '';
      _cantidadController.clear();
      _precioController.clear();
    });
  }

  void _mostrarAviso(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto, style: AppText.cuerpo())));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Comando de voz',
      body: _inicializando
          ? const Center(child: CircularProgressIndicator())
          : !_disponible
              ? const EmptyState(
                  icono: Icons.mic_off_outlined,
                  mensaje:
                      'El reconocimiento de voz no está disponible en este dispositivo.\nVerifica el permiso de micrófono.',
                )
              : _contenido(),
    );
  }

  Widget _contenido() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ejemplos de comandos', style: AppText.tituloSeccion(color: AppColors.verde)),
              const SizedBox(height: AppSpacing.sm),
              Text('"Vender 5 panes a 1200"', style: AppText.secundario()),
              Text('"Agregar 10 gaseosas a 2000"', style: AppText.secundario()),
              Text('"Cuánto stock queda de arroz"', style: AppText.secundario()),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: GestureDetector(
            onTap: _alternarEscucha,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _escuchando ? AppColors.alerta : AppColors.verde,
                boxShadow: [
                  BoxShadow(
                    color: (_escuchando ? AppColors.alerta : AppColors.verde).withValues(alpha: 0.3),
                    blurRadius: _escuchando ? 24 : 10,
                    spreadRadius: _escuchando ? 6 : 2,
                  ),
                ],
              ),
              child: Icon(_escuchando ? Icons.stop : Icons.mic, color: Colors.white, size: 40),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Text(_escuchando ? 'Escuchando... toca para detener' : 'Toca para hablar', style: AppText.secundario()),
        ),
        if (_textoReconocido.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(AppRadius.card)),
            child: Text('"$_textoReconocido"', style: AppText.cuerpo(size: 14)),
          ),
        ],
        if (_resultadoConsulta != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: AppColors.verdeClaro, borderRadius: BorderRadius.circular(AppRadius.card)),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, color: AppColors.verde),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(_resultadoConsulta!, style: AppText.cuerpo(peso: FontWeight.bold))),
              ],
            ),
          ),
        ],
        if (_comando != null &&
            _comando!.tipo != TipoComandoVoz.consultaStock &&
            _comando!.tipo != TipoComandoVoz.desconocido)
          _tarjetaConfirmacion(),
        if (_comando?.tipo == TipoComandoVoz.desconocido)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text('No reconocí ese comando. Prueba con una de las frases de ejemplo de arriba.', style: AppText.secundario()),
          ),
      ],
    );
  }

  Widget _tarjetaConfirmacion() {
    final comando = _comando!;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.verde.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(comando.tipo == TipoComandoVoz.venta ? 'Venta' : 'Entrada de stock', style: AppText.tituloSeccion(color: AppColors.verde)),
          const SizedBox(height: AppSpacing.sm),
          if (_producto == null) ...[
            Text('No encontré un producto parecido a "${comando.nombreProductoDicho}". Elige uno:', style: AppText.secundario()),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<Producto>(
              initialValue: _producto,
              decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.campo))),
              items: _productosActivos.map((p) => DropdownMenuItem(value: p, child: Text(p.nombre, style: AppText.cuerpo()))).toList(),
              onChanged: (p) => setState(() {
                _producto = p;
                if (p?.precioVentaSugerido != null && _precioController.text.isEmpty) {
                  _precioController.text = p!.precioVentaSugerido!.toStringAsFixed(0);
                }
              }),
            ),
          ] else
            Text('Producto: ${_producto!.nombre}', style: AppText.cuerpo(peso: FontWeight.bold)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: StyledTextField(controller: _cantidadController, label: 'Cantidad', tipo: TextInputType.number)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: StyledTextField(
                  controller: _precioController,
                  label: comando.tipo == TipoComandoVoz.venta ? 'Precio' : 'Costo',
                  tipo: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(texto: 'Confirmar', cargando: _guardando, onPressed: _producto == null ? null : _confirmar),
        ],
      ),
    );
  }
}