import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';
import 'precio_bajo_costo_screen.dart';
import 'sin_ventas_recientes_screen.dart';
import 'mercancia_baja_rotacion_screen.dart';
import 'diferencias_inventario_screen.dart';

class OportunidadesScreen extends StatefulWidget {
  const OportunidadesScreen({super.key});

  @override
  State<OportunidadesScreen> createState() => _OportunidadesScreenState();
}

class _OportunidadesScreenState extends State<OportunidadesScreen> {
  late Future<_ResumenOportunidades> _resumenFuture;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _resumenFuture = _construirResumen();
  }

  Future<_ResumenOportunidades> _construirResumen() async {
    final db = DatabaseHelper.instance;

    final precioBajo = await db.getProductosPrecioBajoCosto();
    final sinVentas = await db.getProductosSinVentasRecientes(dias: 30);
    final bajaRotacion = await db.getMercanciaBajaRotacion(dias: 90);
    final ultimasDiferencias = await db.getUltimasDiferenciasInventario();

    final valorInmovilizado = bajaRotacion.fold<double>(
      0,
      (total, fila) => total + (fila['valorInmovilizado'] as num).toDouble(),
    );

    return _ResumenOportunidades(
      precioBajoCosto: precioBajo.length,
      sinVentasRecientes: sinVentas.length,
      diferenciasInventario: ultimasDiferencias.length, // pendiente: módulo de conteo físico
      valorBajaRotacion: valorInmovilizado,
    );
  }

  Future<void> _refrescar() async {
    setState(() => _cargar());
    await _resumenFuture;
  }

  String _formatearMoneda(double valor) => '${valor.toStringAsFixed(0)} Q';

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Qué debo solucionar hoy',
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<_ResumenOportunidades>(
          future: _resumenFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 100),
                  Center(
                    child: Text(
                      'No se pudo cargar el resumen:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: AppText.cuerpo(color: Colors.red),
                    ),
                  ),
                ],
              );
            }

            final r = snapshot.data!;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Revisa estas alertas y oportunidades para mejorar tu negocio.',
                  style: AppText.secundario(size: 14),
                ),
                const SizedBox(height: 16),

                // ---- Grid 2x2 de tarjetas ----
                Row(
                  children: [
                    Expanded(
                      child: _TarjetaOportunidad(
                        icono: Icons.trending_down,
                        color: Colors.red,
                        valor: '${r.precioBajoCosto}',
                        etiqueta: 'Productos con\nprecio bajo costo',
                        onTap: () => _irA(const PrecioBajoCostoScreen()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TarjetaOportunidad(
                        icono: Icons.inventory_outlined,
                        color: Colors.orange,
                        valor: '${r.sinVentasRecientes}',
                        etiqueta: 'Productos sin\nventas recientes',
                        onTap: () => _irA(const SinVentasRecientesScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _TarjetaOportunidad(
                        icono: Icons.fact_check_outlined,
                        color: Colors.blue,
                        valor: '${r.diferenciasInventario}',
                        etiqueta: 'Diferencias de\ninventario',
                        onTap: () => _irA(const DiferenciasInventarioScreen()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TarjetaOportunidad(
                        icono: Icons.savings_outlined,
                        color: Colors.green,
                        valor: _formatearMoneda(r.valorBajaRotacion),
                        etiqueta: 'En mercancía de\nbaja rotación',
                        valorPequeno: true,
                        onTap: () => _irA(const MercanciaBajaRotacionScreen()),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                Text(
                  'Acciones recomendadas',
                  style: AppText.tituloSeccion(color: Colors.black),
                ),
                const SizedBox(height: 8),

                if (r.precioBajoCosto > 0)
                  _AccionRecomendada(
                    icono: Icons.warning_amber_rounded,
                    color: Colors.red,
                    titulo: 'Revisar precios de venta',
                    subtitulo:
                        '${r.precioBajoCosto} producto(s) tienen un precio inferior al costo registrado.',
                    onTap: () => _irA(const PrecioBajoCostoScreen()),
                  ),
                if (r.sinVentasRecientes > 0)
                  _AccionRecomendada(
                    icono: Icons.inventory_outlined,
                    color: Colors.orange,
                    titulo: 'Revisar mercancía estancada',
                    subtitulo:
                        '${r.sinVentasRecientes} producto(s) no registran ventas en los últimos 30 días.',
                    onTap: () => _irA(const SinVentasRecientesScreen()),
                  ),
                if (r.valorBajaRotacion > 0)
                  _AccionRecomendada(
                    icono: Icons.savings_outlined,
                    color: Colors.green,
                    titulo: 'Evaluar productos de baja rotación',
                    subtitulo:
                        '${_formatearMoneda(r.valorBajaRotacion)} en productos con pocas ventas en 90 días.',
                    onTap: () => _irA(const MercanciaBajaRotacionScreen()),
                  ),
                if (r.diferenciasInventario > 0)
                  _AccionRecomendada(
                    icono: Icons.fact_check_outlined,
                    color: Colors.blue,
                    titulo: 'Verificar conteo físico',
                    subtitulo: '${r.diferenciasInventario} producto(s) con diferencias en el inventario.',
                    onTap: () => _irA(const DiferenciasInventarioScreen()),
                  ),
                if (r.precioBajoCosto == 0 && r.sinVentasRecientes == 0 && r.valorBajaRotacion == 0 && r.diferenciasInventario == 0)
                  const EmptyState(
                    icono: Icons.check_circle_outline,
                    mensaje: 'Todo en orden. No hay alertas por ahora.',
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _irA(Widget pantalla) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla))
        .then((_) => _refrescar());
  }
}

class _ResumenOportunidades {
  final int precioBajoCosto;
  final int sinVentasRecientes;
  final int diferenciasInventario;
  final double valorBajaRotacion;

  _ResumenOportunidades({
    required this.precioBajoCosto,
    required this.sinVentasRecientes,
    required this.diferenciasInventario,
    required this.valorBajaRotacion,
  });
}

class _TarjetaOportunidad extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String valor;
  final String etiqueta;
  final bool valorPequeno;
  final VoidCallback onTap;

  const _TarjetaOportunidad({
    required this.icono,
    required this.color,
    required this.valor,
    required this.etiqueta,
    required this.onTap,
    this.valorPequeno = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: color, size: 26),
            const SizedBox(height: 10),
            Text(
              valor,
              style: AppText.tituloSeccion(color: Colors.black)
                  .copyWith(fontSize: valorPequeno ? 16 : 24),
            ),
            const SizedBox(height: 4),
            Text(
              etiqueta,
              style: AppText.secundario(size: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccionRecomendada extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _AccionRecomendada({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icono, color: color),
        ),
        title: Text(titulo, style: AppText.cuerpo(peso: FontWeight.bold)),
        subtitle: Text(subtitulo, style: AppText.cuerpo(size: 13)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}