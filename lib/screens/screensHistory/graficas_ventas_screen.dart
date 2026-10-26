import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'historial_screen.dart';
import 'resumen_financiero_screen.dart';
import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';

class GraficasVentasScreen extends StatefulWidget {
  const GraficasVentasScreen({super.key});

  @override
  State<GraficasVentasScreen> createState() => _GraficasVentasScreenState();
}

class _GraficasVentasScreenState extends State<GraficasVentasScreen>
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
      titulo: 'Gráficas de ventas',
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
          icon: const Icon(Icons.account_balance_wallet_outlined),
          color: Colors.black,
          iconSize: 35,
          tooltip: 'Resumen financiero',
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ResumenFinancieroScreen()),
            );
          },
        ),
      ],
      bottom: TabBar(
        labelColor: Colors.black,
        indicatorColor: Colors.white,
        labelStyle: AppText.cuerpo(),
        controller: _tabController,
        tabs: const [
          Tab(text: 'Mensual'),
          Tab(text: 'Trimestral'),
          Tab(text: 'Anual'),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _GraficaPeriodo(periodo: 'mensual'),
          _GraficaPeriodo(periodo: 'trimestral'),
          _GraficaPeriodo(periodo: 'anual'),
        ],
      ),
    );
  }
}

class _GraficaPeriodo extends StatefulWidget {
  final String periodo;

  const _GraficaPeriodo({required this.periodo});

  @override
  State<_GraficaPeriodo> createState() => _GraficaPeriodoState();
}

class _GraficaPeriodoState extends State<_GraficaPeriodo> {
  late Future<Map<String, List<Map<String, dynamic>>>> _datosFuture;
  final Set<String> _productosSeleccionados = {};

  static const List<Color> _colores = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.brown,
  ];

  @override
  void initState() {
    super.initState();
    _datosFuture = DatabaseHelper.instance.getVentasPorPeriodoPorProducto(
      widget.periodo,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: _datosFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final porProducto = snapshot.data ?? {};

        if (porProducto.isEmpty) {
          return const EmptyState(
            icono: Icons.show_chart,
            mensaje: 'No hay ventas registradas aún',
          );
        }

        final todosLosProductos = porProducto.keys.toList();

        return Column(
          children: [
            // Selector de productos
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: todosLosProductos.map((nombre) {
                  final index = todosLosProductos.indexOf(nombre);
                  final seleccionado = _productosSeleccionados.contains(nombre);
                  return FilterChip(
                    label: Text(nombre, style: AppText.cuerpo(size: 12)),
                    selected: seleccionado,
                    selectedColor: _colores[index % _colores.length].withValues(
                      alpha: 0.3,
                    ),
                    onSelected: (valor) {
                      setState(() {
                        if (valor) {
                          _productosSeleccionados.add(nombre);
                        } else {
                          _productosSeleccionados.remove(nombre);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            Expanded(
              child: _productosSeleccionados.isEmpty
                  ? Center(
                      child: Text(
                        'Selecciona al menos un producto',
                        style: AppText.cuerpo(),
                      ),
                    )
                  : _construirGrafica(porProducto, todosLosProductos),
            ),
          ],
        );
      },
    );
  }

  Widget _construirGrafica(
    Map<String, List<Map<String, dynamic>>> porProducto,
    List<String> todosLosProductos,
  ) {
    Set<String> periodosSet = {};
    for (var nombre in _productosSeleccionados) {
      for (var fila in porProducto[nombre]!) {
        periodosSet.add(fila['periodo'] as String);
      }
    }

    var etiquetas = periodosSet.toList()..sort();

    // Si es mensual, mostrar solo los últimos 6 meses
    if (widget.periodo == 'mensual' && etiquetas.length > 6) {
      etiquetas = etiquetas.sublist(etiquetas.length - 6);
    }

    final List<LineChartBarData> lineas = [];
    double maxY = 0;

    for (final nombre in _productosSeleccionados) {
      final index = todosLosProductos.indexOf(nombre);
      final datosProducto = porProducto[nombre]!;

      final Map<String, double> valoresPorPeriodo = {
        for (final fila in datosProducto)
          fila['periodo'] as String: (fila['totalVendido'] as num).toDouble(),
      };

      final spots = <FlSpot>[];
      for (int j = 0; j < etiquetas.length; j++) {
        final valor = valoresPorPeriodo[etiquetas[j]] ?? 0.0;
        spots.add(FlSpot(j.toDouble(), valor));
        if (valor > maxY) maxY = valor;
      }

      lineas.add(
        LineChartBarData(
          spots: spots,
          isCurved: false,
          preventCurveOverShooting: true,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          color: _colores[index % _colores.length],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 16, 15, 10),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          lineBarsData: lineas,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 40),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= etiquetas.length) {
                    return const SizedBox.shrink();
                  }
                  if (value != index.toDouble()) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _formatearEtiqueta(etiquetas[index], widget.periodo),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: true),
        ),
      ),
    );
  }

  String _formatearEtiqueta(String periodo, String tipoPeriodo) {
    const meses = ['Ene','Feb','Mar','Abr','May','Jun',
                    'Jul','Ago','Sep','Oct','Nov','Dic',];

    final partes = periodo.split('-');

    if (tipoPeriodo == 'mensual') {
      final mesIndex = int.parse(partes[1]) - 1;
      return meses[mesIndex];
    } else if (tipoPeriodo == 'trimestral') {
      final anio = partes[0].substring(2);
      return '${partes[1]} \'$anio';
    } else {
      return periodo;
    }
  }
}