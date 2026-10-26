import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';
import 'graficas_ventas_screen.dart';
import 'historial_screen.dart';

class ResumenFinancieroScreen extends StatefulWidget {
  const ResumenFinancieroScreen({super.key});

  @override
  State<ResumenFinancieroScreen> createState() => _ResumenFinancieroScreenState();
}

class _ResumenFinancieroScreenState extends State<ResumenFinancieroScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Resumen financiero',
      acciones: [
        IconButton(
          icon: const Icon(Icons.receipt_long_outlined),
          color: Colors.black,
          iconSize: 35,
          tooltip: 'Historial',
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HistorialScreen()),
            );
          },
        ),
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
      ],
      bottom: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'Mensual'),
          Tab(text: 'Trimestral'),
          Tab(text: 'Total'),
        ],
        indicatorColor: Colors.white,
        labelColor: Colors.black,
        labelStyle: AppText.cuerpo(size: 16),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ResumenPorPeriodo(periodo: 'mensual'),
          _ResumenPorPeriodo(periodo: 'trimestral'),
          _ResumenTotal(),
        ],
      ),
    );
  }
}

class _ResumenPorPeriodo extends StatefulWidget {
  final String periodo;

  const _ResumenPorPeriodo({required this.periodo});

  @override
  State<_ResumenPorPeriodo> createState() => _ResumenPorPeriodoState();
}

class _ResumenPorPeriodoState extends State<_ResumenPorPeriodo> {
  List<String> _periodos = [];
  String? _periodoSeleccionado;
  Map<String, double>? _resumen;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarPeriodos();
  }

  Future<void> _cargarPeriodos() async {
    final periodos = await DatabaseHelper.instance.getPeriodosDisponibles(widget.periodo);
    setState(() {
      _periodos = periodos;
      _periodoSeleccionado = periodos.isNotEmpty ? periodos.first : null;
      _cargando = false;
    });
    if (_periodoSeleccionado != null) {
      _cargarResumen(_periodoSeleccionado!);
    }
  }

  Future<void> _cargarResumen(String valorPeriodo) async {
    final resumen = await DatabaseHelper.instance
        .getResumenFinancieroPorPeriodo(widget.periodo, valorPeriodo);
    setState(() => _resumen = resumen);
  }

  String _formatearMoneda(double valor) => '${valor.toStringAsFixed(0)} Q';

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_periodos.isEmpty) {
      return const EmptyState(
        icono: Icons.receipt_long_outlined,
        mensaje: 'No hay movimientos registrados aún',
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _periodoSeleccionado,
            decoration: InputDecoration(
              labelText: 'Periodo',
              border: const OutlineInputBorder(),
              labelStyle: AppText.cuerpo(size: 20),
            ),
            style: AppText.cuerpo(size: 17, color: Colors.black),
            items: _periodos.map((p) {
              return DropdownMenuItem(value: p, child: Text(p));
            }).toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _periodoSeleccionado = value);
              _cargarResumen(value);
            },
          ),
          const SizedBox(height: 16),
          if (_resumen == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView(
                children: [
                  _TarjetaResumen(
                    titulo: 'Gastado en reposición',
                    valor: _formatearMoneda(_resumen!['totalGastado'] ?? 0),
                    icono: Icons.shopping_cart_outlined,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 12),
                  _TarjetaResumen(
                    titulo: 'Total en ventas',
                    valor: _formatearMoneda(_resumen!['totalVentas'] ?? 0),
                    icono: Icons.point_of_sale,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 12),
                  _TarjetaResumen(
                    titulo: 'Costo de lo vendido',
                    valor: _formatearMoneda(_resumen!['costoVendido'] ?? 0),
                    icono: Icons.inventory_2_outlined,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  _TarjetaResumen(
                    titulo: 'Pérdidas por faltantes',
                    valor: _formatearMoneda(_resumen!['costoPerdidas'] ?? 0),
                    icono: Icons.remove_circle_outline,
                    color: Colors.deepOrange,
                  ),
                  const SizedBox(height: 12),
                  _TarjetaResumen(
                    titulo: 'Ganancias por sobrantes',
                    valor: _formatearMoneda(_resumen!['valorGananciasSobrantes'] ?? 0),
                    icono: Icons.add_circle_outline,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 12),
                  _TarjetaResumen(
                    titulo: 'Ganancia',
                    valor: _formatearMoneda(_resumen!['ganancia'] ?? 0),
                    icono: (_resumen!['ganancia'] ?? 0) >= 0
                        ? Icons.trending_up
                        : Icons.trending_down,
                    color: (_resumen!['ganancia'] ?? 0) >= 0 ? Colors.green : Colors.red,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ResumenTotal extends StatefulWidget {
  const _ResumenTotal();

  @override
  State<_ResumenTotal> createState() => _ResumenTotalState();
}

class _ResumenTotalState extends State<_ResumenTotal> {
  late Future<Map<String, double>> _resumenFuture;

  @override
  void initState() {
    super.initState();
    _resumenFuture = DatabaseHelper.instance.getResumenFinanciero();
  }

  String _formatearMoneda(double valor) => ' ${valor.toStringAsFixed(0)} Q';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, double>>(
      future: _resumenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _TarjetaResumen(
              titulo: 'Gastado en reposición',
              valor: _formatearMoneda(data['totalGastado'] ?? 0),
              icono: Icons.shopping_cart_outlined,
              color: Colors.orange,
            ),
            const SizedBox(height: 12),
            _TarjetaResumen(
              titulo: 'Total en ventas',
              valor: _formatearMoneda(data['totalVentas'] ?? 0),
              icono: Icons.point_of_sale,
              color: Colors.blue,
            ),
            const SizedBox(height: 12),
            _TarjetaResumen(
              titulo: 'Costo de lo vendido',
              valor: _formatearMoneda(data['costoVendido'] ?? 0),
              icono: Icons.inventory_2_outlined,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            _TarjetaResumen(
              titulo: 'Pérdidas por faltantes',
              valor: _formatearMoneda(data['costoPerdidas'] ?? 0),
              icono: Icons.remove_circle_outline,
              color: Colors.deepOrange,
            ),
            const SizedBox(height: 12),
            _TarjetaResumen(
              titulo: 'Ganancias por sobrantes',
              valor: _formatearMoneda(data['valorGananciasSobrantes'] ?? 0),
              icono: Icons.add_circle_outline,
              color: Colors.blue,
            ),
            const SizedBox(height: 12),
            _TarjetaResumen(
              titulo: 'Ganancia',
              valor: _formatearMoneda(data['ganancia'] ?? 0),
              icono: (data['ganancia'] ?? 0) >= 0 ? Icons.trending_up : Icons.trending_down,
              color: (data['ganancia'] ?? 0) >= 0 ? Colors.green : Colors.red,
            ),
          ],
        );
      },
    );
  }
}

class _TarjetaResumen extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;

  const _TarjetaResumen({
    required this.titulo,
    required this.valor,
    required this.icono,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icono, color: color, size: 32),
            const SizedBox(width: 16),
            Expanded(child: Text(titulo, style: AppText.cuerpo(size: 18))),
            Text(
              valor,
              style: AppText.cuerpo(
                size: 19,
                color: color,
                peso: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}