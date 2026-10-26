import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/menu_acciones_sheet.dart';
import '../screensServices/export_service.dart';
import '../screensServices/import_service.dart';
import 'graficas_ventas_screen.dart';
import 'resumen_financiero_screen.dart';
import 'seleccionar_rango_informe_screen.dart';
import '../screensServices/borrar_datos_screen.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  static const _tamanoPagina = 100;

  final List<Map<String, dynamic>> _movimientos = [];
  bool _cargandoInicial = true;
  bool _cargandoMas = false;
  bool _hayMas = true;
  late Future<Map<String, double>> _resumenFuture;

  @override
  void initState() {
    super.initState();
    _resumenFuture = DatabaseHelper.instance.getResumenFinanciero();
    _cargarPrimeraPagina();
  }

  Future<void> _cargarPrimeraPagina() async {
    setState(() {
      _movimientos.clear();
      _hayMas = true;
      _cargandoInicial = true;
    });

    final pagina = await DatabaseHelper.instance.getMovimientosPaginados(
      limite: _tamanoPagina,
      offset: 0,
    );

    if (!mounted) return;
    setState(() {
      _movimientos.addAll(pagina);
      _hayMas = pagina.length == _tamanoPagina;
      _cargandoInicial = false;
    });
  }

  Future<void> _cargarMas() async {
    if (_cargandoMas || !_hayMas) return;
    setState(() => _cargandoMas = true);

    final pagina = await DatabaseHelper.instance.getMovimientosPaginados(
      limite: _tamanoPagina,
      offset: _movimientos.length,
    );

    if (!mounted) return;
    setState(() {
      _movimientos.addAll(pagina);
      _hayMas = pagina.length == _tamanoPagina;
      _cargandoMas = false;
    });
  }

  Future<void> _refrescar() async {
    setState(
      () => _resumenFuture = DatabaseHelper.instance.getResumenFinanciero(),
    );
    await _cargarPrimeraPagina();
  }

  String _formatearFecha(String isoFecha) {
    final fecha = DateTime.parse(isoFecha);
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}';
  }

  Future<void> _exportar() async {
    bool mostrandoAviso = false;

    // Si en 1.5s la exportación no ha terminado, probablemente hay
    // muchos datos: recién ahí se muestra el aviso, para no generar
    // ruido en el caso normal (pocos productos/movimientos).
    final temporizador = Future.delayed(const Duration(milliseconds: 3000), () {
      if (!mounted) return;
      mostrandoAviso = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Hay muchos datos, esto puede tardar un momento...', style: AppText.cuerpo(color: Colors.white))),
            ],
          ),
          duration: const Duration(seconds: 30), // se oculta manualmente al terminar
          backgroundColor: AppColors.verde,
        ),
      );
    });

    try {
      await ExportService.exportarYCompartir();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e', style: AppText.cuerpo())),
        );
      }
    } finally {
      temporizador.ignore(); // cancela el aviso si no alcanzó a dispararse
      if (mounted && mostrandoAviso) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    }
  }

  Future<void> _importar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Importar desde Excel', style: AppText.tituloSeccion()),
        content: Text(
          'Esto va a crear productos y movimientos a partir del archivo '
          'seleccionado. Úsalo solo para restaurar un respaldo en una '
          'instalación limpia: importar el mismo archivo más de una vez '
          'duplicará los movimientos.',
          style: AppText.cuerpo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: AppText.cuerpo()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Continuar', style: AppText.cuerpo()),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      final resultado = await ImportService.importarDesdeExcel();

      if (!mounted) return;

      if (resultado.cancelado) return;

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Importación completada', style: AppText.tituloSeccion()),
          content: Text(
            'Productos creados: ${resultado.productosCreados}\n'
            'Productos ya existentes (reutilizados): ${resultado.productosReutilizados}\n'
            'Movimientos importados: ${resultado.movimientosImportados}\n'
            'Movimientos omitidos: ${resultado.movimientosOmitidos}',
            style: AppText.cuerpo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Aceptar', style: AppText.cuerpo()),
            ),
          ],
        ),
      );

      _refrescar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al importar: $e', style: AppText.cuerpo()),
          ),
        );
      }
    }
  }

  Future<void> _generarInforme() async {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const SeleccionarRangoInformeScreen(),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al generar el informe: $e',
              style: AppText.cuerpo(),
            ),
          ),
        );
      }
    }
  }

  double? _calcularResultado(
    String tipo,
    int cantidad,
    double precio,
    double costoLote,
  ) {
    switch (tipo) {
      case 'salida':
        return (precio - costoLote) *
            cantidad; // ganancia o pérdida real de esa venta
      case 'perdida':
        return -(costoLote * cantidad); // faltante detectado en conteo físico
      case 'ganancia':
        return precio * cantidad; // sobrante detectado en conteo físico
      default:
        return null; // 'entrada': es un gasto, no una ganancia/pérdida
    }
  }

  String _etiquetaTipoDetalle(String tipo) {
    switch (tipo) {
      case 'entrada':
        return 'Entrada de stock';
      case 'salida':
        return 'Venta';
      case 'perdida':
        return 'Pérdida (faltante)';
      case 'ganancia':
        return 'Ganancia (sobrante)';
      default:
        return tipo;
    }
  }

  void _mostrarDetalle(Map<String, dynamic> m) {
    final tipo = m['tipo'] as String;
    final cantidad = m['cantidad'] as int;
    final precio = (m['precioUnitario'] as num).toDouble();
    final costoLote = (m['costoLote'] as num).toDouble();
    final fechaLote = DateTime.parse(m['fechaLote'] as String);
    final total = cantidad * precio;
    final resultado = _calcularResultado(tipo, cantidad, precio, costoLote);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m['nombreProducto'] as String,
                style: AppText.tituloPantalla(),
              ),
              const SizedBox(height: 4),
              Text(_etiquetaTipoDetalle(tipo), style: AppText.secundario()),
              const Divider(height: 28),
              _filaDetalle('Cantidad', '$cantidad ${m['unidadProducto']}'),
              _filaDetalle('Precio unitario', '\$${precio.toStringAsFixed(0)}'),
              _filaDetalle(
                'Total del movimiento',
                '\$${total.toStringAsFixed(0)}',
              ),
              const Divider(height: 28),
              Text(
                'Origen del costo (lote)',
                style: AppText.cuerpo(peso: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              _filaDetalle(
                'Lote ingresado el',
                _formatearFecha(fechaLote.toIso8601String()),
              ),
              _filaDetalle(
                'Costo del lote',
                '\$${costoLote.toStringAsFixed(0)} / unidad',
              ),
              if (resultado != null) ...[
                const Divider(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      resultado >= 0 ? 'Ganancia generada' : 'Pérdida generada',
                      style: AppText.cuerpo(peso: FontWeight.bold),
                    ),
                    Text(
                      '\$${resultado.abs().toStringAsFixed(0)}',
                      style: AppText.tituloSeccion(
                        color: resultado >= 0
                            ? AppColors.verde
                            : AppColors.alerta,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Historial',
      acciones: [
        IconButton(
          icon: const Icon(Icons.show_chart),
          color: Colors.black,
          iconSize: 35,
          tooltip: 'Gráficas de ventas',
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const GraficasVentasScreen()),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.account_balance_wallet_outlined),
          color: Colors.black,
          iconSize: 35,
          tooltip: 'Resumen financiero',
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const ResumenFinancieroScreen(),
              ),
            );
          },
        ),
      ],
      body: Column(
        children: [
          FutureBuilder<Map<String, double>>(
            future: _resumenFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox(height: 100);
              return _tarjetaResumenRapido(snapshot.data!);
            },
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refrescar,
              child: _cargandoInicial
                  ? const Center(child: CircularProgressIndicator())
                  : _movimientos.isEmpty
                  ? const EmptyState(
                      icono: Icons.receipt_long_outlined,
                      mensaje: 'No hay movimientos registrados aún',
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notificacion) {
                        if (notificacion.metrics.pixels >=
                            notificacion.metrics.maxScrollExtent - 200) {
                          _cargarMas();
                        }
                        return false;
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: _movimientos.length + (_hayMas ? 1 : 0),
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == _movimientos.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }

                          final m = _movimientos[index];
                          final tipo = m['tipo'] as String;
                          final cantidad = m['cantidad'] as int;
                          final precio = (m['precioUnitario'] as num)
                              .toDouble();
                          final costoLote = (m['costoLote'] as num).toDouble();
                          final total = cantidad * precio;
                          final resultado = _calcularResultado(
                            tipo,
                            cantidad,
                            precio,
                            costoLote,
                          );

                          late final IconData icono;
                          late final Color color;
                          late final String etiqueta;

                          switch (tipo) {
                            case 'entrada':
                              icono = Icons.arrow_downward;
                              color = Colors.green;
                              etiqueta = 'Entrada';
                              break;
                            case 'salida':
                              icono = Icons.arrow_upward;
                              color = Colors.red;
                              etiqueta = 'Salida';
                              break;
                            case 'perdida':
                              icono = Icons.remove_circle_outline;
                              color = Colors.deepOrange;
                              etiqueta = 'Pérdida (faltante)';
                              break;
                            case 'ganancia':
                              icono = Icons.add_circle_outline;
                              color = Colors.blue;
                              etiqueta = 'Ganancia (sobrante)';
                              break;
                            default:
                              icono = Icons.help_outline;
                              color = Colors.grey;
                              etiqueta = tipo;
                          }

                          return ListTile(
                            onTap: () => _mostrarDetalle(m),
                            leading: CircleAvatar(
                              backgroundColor: color.withValues(alpha: 0.15),
                              child: Icon(icono, color: color),
                            ),
                            title: Text(
                              m['nombreProducto'] as String,
                              style: AppText.cuerpo(size: 19),
                            ),
                            subtitle: Text(
                              '${_formatearFecha(m['fecha'] as String)} · $etiqueta · $cantidad unid.',
                              style: AppText.cuerpo(size: 15),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '\$${total.toStringAsFixed(0)}',
                                  style: AppText.cuerpo(peso: FontWeight.bold),
                                ),
                                if (resultado != null)
                                  Text(
                                    '${resultado >= 0 ? '+' : ''}\$${resultado.toStringAsFixed(0)}',
                                    style: AppText.secundario(size: 11)
                                        .copyWith(
                                          color: resultado >= 0
                                              ? AppColors.verde
                                              : AppColors.alerta,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => mostrarMenuAcciones(
          context,
          titulo: 'Datos del negocio',
          acciones: [
            AccionMenu(
              icono: Icons.ios_share,
              titulo: 'Exportar a Excel',
              subtitulo: 'Respaldo completo de productos y movimientos',
              onTap: _exportar,
            ),
            AccionMenu(
              icono: Icons.download_outlined,
              color: Colors.blue,
              titulo: 'Importar desde Excel',
              subtitulo: 'Restaura datos desde un respaldo anterior',
              onTap: _importar,
            ),
            AccionMenu(
              icono: Icons.picture_as_pdf_outlined,
              color: Colors.red.shade700,
              titulo: 'Informe PDF',
              subtitulo: 'Resumen visual del negocio por periodo',
              onTap: _generarInforme,
            ),
            AccionMenu(
              icono: Icons.delete_forever_outlined,
              color: AppColors.advertencia,
              titulo: 'Borrar todos los datos',
              subtitulo: 'Exporta un respaldo y limpia la app por completo',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BorrarDatosScreen()),
                );
              },
            ),
          ],
        ),
        icon: const Icon(Icons.menu),
        label: Text(
          'Más opciones',
          style: AppText.tituloSeccion(color: Colors.white),
        ),
        backgroundColor: AppColors.verde,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _tarjetaResumenRapido(Map<String, double> r) {
    final ganancia = r['ganancia'] ?? 0;
    final positivo = ganancia >= 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: positivo
            ? AppColors.verdeClaro
            : AppColors.alerta.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: (positivo ? AppColors.verde : AppColors.alerta).withValues(
            alpha: 0.3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    positivo ? Icons.trending_up : Icons.trending_down,
                    color: positivo ? AppColors.verde : AppColors.alerta,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Ganancia neta',
                    style: AppText.cuerpo(
                      size: 14,
                      color: AppColors.textoSecundario,
                    ),
                  ),
                ],
              ),
              Text(
                '\$${ganancia.toStringAsFixed(0)}',
                style: AppText.tituloSeccion(
                  color: positivo ? AppColors.verde : AppColors.alerta,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _miniDato('Ventas', r['totalVentas'])),
              Expanded(child: _miniDato('Compras', r['totalGastado'])),
              Expanded(child: _miniDato('Pérdidas', r['costoPerdidas'])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniDato(String etiqueta, double? valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: AppText.secundario(size: 11)),
        Text(
          '\$${(valor ?? 0).toStringAsFixed(0)}',
          style: AppText.cuerpo(size: 13, peso: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _filaDetalle(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: AppText.secundario()),
          Text(valor, style: AppText.cuerpo(size: 14)),
        ],
      ),
    );
  }
}
