import 'dart:math' as math;

// =====================================================================
// Cálculos del informe SIN dependencias de pdf ni de la base de datos.
// Reciben listas/mapas y devuelven resultados simples, así se pueden
// probar con datos inventados y los errores no se mezclan con el diseño.
// =====================================================================

/// Umbrales de fiabilidad. Todo en un solo lugar para ajustarlos fácil.
class Umbrales {
  /// Mínimo de días para comparar contra el periodo anterior.
  static const diasComparativo = 7;

  /// Mínimo de días con historial para estimar consumo y reposición.
  static const diasReposicion = 14;

  /// Mínimo de días con historial para el análisis Pareto.
  static const diasPareto = 14;

  /// Mínimo de productos con ventas para que el Pareto tenga sentido.
  static const productosPareto = 5;

  /// Mínimo de registros de venta para analizar horas de actividad.
  static const registrosHoras = 20;

  /// Unidades vendidas por debajo de las cuales la estimación de un
  /// producto se marca como débil.
  static const unidadesMinProducto = 3;

  /// Días de inventario que se quiere tener cubiertos al reponer.
  static const diasObjetivoStock = 14;
}

/// Resultado de evaluar si un dato es confiable. [motivo] explica por qué no.
class Confianza {
  final bool baja;
  final String? motivo;
  const Confianza.ok()
      : baja = false,
        motivo = null;
  const Confianza.baja(String this.motivo) : baja = true;
}

/// Días que realmente respaldan los números del informe.
class ContextoPeriodo {
  final DateTime inicio;
  final DateTime fin;
  final DateTime? primeraVenta;

  /// Días calendario del rango pedido (inclusive).
  final int diasPeriodo;

  /// Días del rango en los que ya existía historial de ventas.
  /// Si la app se empezó a usar a mitad del rango, este número es menor.
  final int diasConHistorial;

  /// Días distintos en los que hubo al menos una venta.
  final int diasConVentas;

  ContextoPeriodo._(
    this.inicio,
    this.fin,
    this.primeraVenta,
    this.diasPeriodo,
    this.diasConHistorial,
    this.diasConVentas,
  );

  factory ContextoPeriodo.calcular({
    required DateTime inicio,
    required DateTime fin,
    required DateTime? primeraVenta,
    required int diasConVentas,
  }) {
    final ini = _soloFecha(inicio);
    final fi = _soloFecha(fin);
    final diasPeriodo = math.max(1, fi.difference(ini).inDays + 1);

    int conHistorial = 0;
    if (primeraVenta != null) {
      final primera = _soloFecha(primeraVenta);
      final desde = primera.isAfter(ini) ? primera : ini;
      conHistorial = fi.isBefore(desde) ? 0 : fi.difference(desde).inDays + 1;
    }

    return ContextoPeriodo._(
      ini,
      fi,
      primeraVenta == null ? null : _soloFecha(primeraVenta),
      diasPeriodo,
      conHistorial,
      diasConVentas,
    );
  }

  /// Inicio del periodo anterior, de igual duración y pegado al actual.
  DateTime get inicioAnterior => DateTime(inicio.year, inicio.month, inicio.day - diasPeriodo);

  /// Fin del periodo anterior (el día antes de [inicio]).
  DateTime get finAnterior => DateTime(inicio.year, inicio.month, inicio.day - 1);

  static DateTime _soloFecha(DateTime f) => DateTime(f.year, f.month, f.day);
}

// ---------------------------------------------------------------------
// COMPARATIVO
// ---------------------------------------------------------------------

class Variacion {
  /// null cuando no se puede calcular (periodo anterior en cero).
  final double? porcentaje;
  const Variacion(this.porcentaje);

  bool get disponible => porcentaje != null;
  bool get sube => (porcentaje ?? 0) > 0.05;
  bool get baja => (porcentaje ?? 0) < -0.05;

  /// "+12,3%" / "-5,0%" / "sin datos previos".
  String get texto {
    final p = porcentaje;
    if (p == null) return 'sin datos previos';
    final signo = p > 0.05 ? '+' : '';
    return '$signo${p.toStringAsFixed(1).replaceAll('.', ',')}%';
  }
}

Variacion variacion(num actual, num previo) {
  if (previo == 0) return const Variacion(null);
  return Variacion((actual - previo) / previo.abs() * 100);
}

Confianza evaluarComparativo({
  required ContextoPeriodo ctx,
  required double ventasPrevias,
}) {
  if (ctx.primeraVenta == null) {
    return const Confianza.baja('Todavía no hay ventas registradas, no hay con qué comparar.');
  }
  if (ventasPrevias == 0) {
    return const Confianza.baja(
      'No hubo ventas en el periodo anterior, por eso no se puede calcular la variación.',
    );
  }
  if (ctx.diasPeriodo < Umbrales.diasComparativo) {
    return Confianza.baja(
      'El periodo analizado es de solo ${ctx.diasPeriodo} día(s). Con menos de ${Umbrales.diasComparativo} días, '
      'un solo día bueno o malo cambia mucho la variación.',
    );
  }
  if (ctx.primeraVenta!.isAfter(ctx.inicioAnterior)) {
    final d = ctx.primeraVenta!;
    return Confianza.baja(
      'El periodo anterior solo tiene datos parciales: tu historial de ventas empieza el '
      '${_dd(d)}/${_mm(d)}/${d.year}. La variación puede estar exagerada.',
    );
  }
  return const Confianza.ok();
}

// ---------------------------------------------------------------------
// PARETO
// ---------------------------------------------------------------------

class FilaPareto {
  final String nombre;
  final double ingreso;
  final double porcentaje; // participación en el ingreso total (0-100)
  final double acumulado; // porcentaje acumulado (0-100)
  const FilaPareto(this.nombre, this.ingreso, this.porcentaje, this.acumulado);
}

class ResultadoPareto {
  /// Productos (en orden) necesarios para llegar al 80% del ingreso.
  final List<FilaPareto> principales;
  final int totalProductos;
  final double totalIngreso;
  final Confianza confianza;

  const ResultadoPareto(this.principales, this.totalProductos, this.totalIngreso, this.confianza);

  int get cuantosHacen80 => principales.length;
}

/// Calcula qué productos concentran el 80% del ingreso.
/// Devuelve null si no hay ventas que analizar.
ResultadoPareto? calcularPareto(List<Map<String, dynamic>> ranking, ContextoPeriodo ctx) {
  final lista = ranking
      .where((p) => ((p['ingresoTotal'] as num?)?.toDouble() ?? 0) > 0)
      .toList()
    ..sort((a, b) => (b['ingresoTotal'] as num).compareTo(a['ingresoTotal'] as num));
  if (lista.isEmpty) return null;

  final total = lista.fold<double>(0, (t, p) => t + (p['ingresoTotal'] as num).toDouble());
  final filas = <FilaPareto>[];
  var acumulado = 0.0;

  for (final p in lista) {
    final ingreso = (p['ingresoTotal'] as num).toDouble();
    final pct = ingreso / total * 100;
    acumulado += pct;
    filas.add(FilaPareto(p['nombre'] as String, ingreso, pct, acumulado));
    if (acumulado >= 80) break;
  }

  Confianza confianza = const Confianza.ok();
  if (lista.length < Umbrales.productosPareto) {
    confianza = Confianza.baja(
      'Solo ${lista.length} producto(s) tuvieron ventas. Con menos de ${Umbrales.productosPareto} productos, '
      'la concentración no dice mucho.',
    );
  } else if (ctx.diasConHistorial < Umbrales.diasPareto) {
    confianza = Confianza.baja(
      'Solo hay ${ctx.diasConHistorial} día(s) de historial en este periodo. Con menos de ${Umbrales.diasPareto} días, '
      'el ranking puede cambiar bastante la próxima semana.',
    );
  }

  return ResultadoPareto(filas, lista.length, total, confianza);
}

// ---------------------------------------------------------------------
// REPOSICIÓN
// ---------------------------------------------------------------------

class FilaReposicion {
  final String nombre;
  final String unidad;
  final int stock;
  final int stockMinimo;
  final double consumoDiario;

  /// Días que le quedan al stock actual al ritmo del periodo.
  final double diasRestantes;

  /// Unidades sugeridas para cubrir [Umbrales.diasObjetivoStock] días.
  final int sugerido;

  /// true cuando se vendieron muy pocas unidades para estimar bien.
  final bool debil;

  const FilaReposicion({
    required this.nombre,
    required this.unidad,
    required this.stock,
    required this.stockMinimo,
    required this.consumoDiario,
    required this.diasRestantes,
    required this.sugerido,
    required this.debil,
  });
}

class ResultadoReposicion {
  final List<FilaReposicion> filas;

  /// Productos con stock bajo que no vendieron nada en el periodo
  /// (no se puede estimar cuándo se agotan).
  final List<String> bajoSinVentas;

  final Confianza confianza;
  const ResultadoReposicion(this.filas, this.bajoSinVentas, this.confianza);
}

/// Evalúa un único producto: si necesita reposición, devuelve la fila
/// con el cálculo; si no la necesita, devuelve `null`. Es la pieza
/// reutilizable detrás de [calcularReposicion] (que la aplica a todo
/// el catálogo) y de cualquier chequeo puntual sobre un solo producto.
FilaReposicion? evaluarFilaReposicion({
  required String nombre,
  required String unidad,
  required int stock,
  required int stockMinimo,
  required double unidadesVendidas,
  required int diasHistorial,
}) {
  if (unidadesVendidas <= 0) return null;

  final dias = math.max(1, diasHistorial);
  final consumo = unidadesVendidas / dias;
  final diasRestantes = stock / consumo;
  final bajoMinimo = stock < stockMinimo;
  final necesita = diasRestantes <= Umbrales.diasObjetivoStock || bajoMinimo;
  if (!necesita) return null;

  final sugerido = math.max(0, (consumo * Umbrales.diasObjetivoStock - stock).ceil());

  return FilaReposicion(
    nombre: nombre,
    unidad: unidad,
    stock: stock,
    stockMinimo: stockMinimo,
    consumoDiario: consumo,
    diasRestantes: diasRestantes,
    sugerido: sugerido,
    debil: unidadesVendidas < Umbrales.unidadesMinProducto,
  );
}

/// [productosConStock]: filas de `getProductosConStockBatch()` (id, nombre,
/// unidad, stockMinimo, activo, stockActual).
/// [ranking]: filas de `getRankingProductosPorRango()` (id, unidadesVendidas).
ResultadoReposicion calcularReposicion({
  required List<Map<String, dynamic>> productosConStock,
  required List<Map<String, dynamic>> ranking,
  required ContextoPeriodo ctx,
}) {
  final unidadesPorProducto = <int, double>{
    for (final r in ranking)
      (r['id'] as num).toInt(): (r['unidadesVendidas'] as num?)?.toDouble() ?? 0,
  };

  // Se divide entre los días con historial real, no entre el rango pedido:
  // si la app se empezó a usar hace 5 días, el consumo diario es sobre 5.
  //final dias = math.max(1, ctx.diasConHistorial);
  final filas = <FilaReposicion>[];
  final sinVentas = <String>[];

  for (final p in productosConStock) {
    if ((p['activo'] as num?)?.toInt() != 1) continue;

    final id = (p['id'] as num).toInt();
    final stock = (p['stockActual'] as num?)?.toInt() ?? 0;
    final minimo = (p['stockMinimo'] as num?)?.toInt() ?? 0;
    final unidades = unidadesPorProducto[id] ?? 0;
    final bajoMinimo = stock < minimo;

    if (unidades <= 0) {
      if (bajoMinimo) sinVentas.add(p['nombre'] as String);
      continue;
    }

    final fila = evaluarFilaReposicion(
      nombre: p['nombre'] as String,
      unidad: (p['unidad'] as String?) ?? '',
      stock: stock,
      stockMinimo: minimo,
      unidadesVendidas: unidades,
      diasHistorial: ctx.diasConHistorial,
    );
    if (fila != null) filas.add(fila);
  }

  filas.sort((a, b) => a.diasRestantes.compareTo(b.diasRestantes));

  Confianza confianza = const Confianza.ok();
  if (ctx.diasConHistorial < Umbrales.diasReposicion) {
    confianza = Confianza.baja(
      'Solo hay ${ctx.diasConHistorial} día(s) de historial de ventas. Con menos de ${Umbrales.diasReposicion} días, '
      'el consumo diario es una estimación muy inestable; tómala como referencia, no como cifra exacta.',
    );
  }

  return ResultadoReposicion(filas, sinVentas, confianza);
}

// ---------------------------------------------------------------------
// HORAS DE ACTIVIDAD
// ---------------------------------------------------------------------

Confianza evaluarHoras({required int numVentas, required ContextoPeriodo ctx}) {
  if (numVentas < Umbrales.registrosHoras) {
    return Confianza.baja(
      'Solo hay $numVentas registro(s) de venta. Con menos de ${Umbrales.registrosHoras}, '
      'las horas de mayor actividad pueden ser casualidad.',
    );
  }
  return const Confianza.ok();
}

// ---------------------------------------------------------------------
// RESUMEN EJECUTIVO
// ---------------------------------------------------------------------

class LineaResumen {
  final String texto;
  final bool alerta;
  const LineaResumen(this.texto, {this.alerta = false});
}

/// Arma hasta 4 frases con reglas simples sobre los datos (sin IA).
List<LineaResumen> generarResumenEjecutivo({
  required double totalVentas,
  required double ganancia,
  required Variacion variacionVentas,
  required bool comparativoConfiable,
  required List<Map<String, dynamic>> ranking,
  required ResultadoPareto? pareto,
  required ResultadoReposicion reposicion,
  required List<Map<String, dynamic>> bajaRotacion,
  required bool hayDatosLimitados,
}) {
  final lineas = <LineaResumen>[];

  if (totalVentas <= 0) {
    return [
      const LineaResumen('No hay ventas registradas en este periodo.'),
      if (hayDatosLimitados)
        const LineaResumen('Algunos análisis se omiten por falta de datos.', alerta: true),
    ];
  }

  // 1) Ventas y tendencia
  final margen = ganancia / totalVentas * 100;
  var l1 = 'Vendiste ${moneda(totalVentas)} con una ganancia bruta de ${moneda(ganancia)} '
      '(margen ${margen.toStringAsFixed(1).replaceAll('.', ',')}%)';
  if (variacionVentas.disponible && comparativoConfiable) {
    final v = variacionVentas.texto;
    l1 += variacionVentas.sube
        ? ', $v frente al periodo anterior.'
        : variacionVentas.baja
            ? ', $v frente al periodo anterior.'
            : ', igual que el periodo anterior.';
  } else {
    l1 += '.';
  }
  lineas.add(LineaResumen(l1));

  // 2) Producto líder + concentración
  if (ranking.isNotEmpty) {
    final top = [...ranking]
      ..sort((a, b) => (b['gananciaEstimada'] as num).compareTo(a['gananciaEstimada'] as num));
    var l2 = '${top.first['nombre']} fue el producto más rentable';
    if (pareto != null && !pareto.confianza.baja) {
      l2 += ' y ${pareto.cuantosHacen80} de ${pareto.totalProductos} producto(s) generan el 80% de tus ingresos.';
    } else {
      l2 += '.';
    }
    lineas.add(LineaResumen(l2));
  }

  // 3) Alerta principal: agotamiento > inmovilizado > sin alertas
  if (reposicion.filas.isNotEmpty) {
    final f = reposicion.filas.first;
    final dias = f.diasRestantes < 1 ? 'menos de un día' : '${f.diasRestantes.floor()} día(s)';
    lineas.add(LineaResumen(
      '${f.nombre} se agotaría en aproximadamente $dias al ritmo actual; conviene reponerlo.',
      alerta: true,
    ));
  } else if (bajaRotacion.isNotEmpty) {
    final peor = [...bajaRotacion]
      ..sort((a, b) => (b['valorInmovilizado'] as num).compareTo(a['valorInmovilizado'] as num));
    lineas.add(LineaResumen(
      'Tienes ${moneda(peor.first['valorInmovilizado'])} inmovilizados en "${peor.first['nombre']}" sin ventas recientes.',
      alerta: true,
    ));
  } else {
    lineas.add(const LineaResumen('No se detectaron alertas críticas de inventario.'));
  }

  // 4) Aviso de fiabilidad
  if (hayDatosLimitados) {
    lineas.add(const LineaResumen(
      'Algunos análisis tienen pocos datos y están marcados como "datos limitados"; tómalos como referencia.',
      alerta: true,
    ));
  }

  return lineas;
}

// ---------------------------------------------------------------------
// FORMATOS COMPARTIDOS
// ---------------------------------------------------------------------

/// 1250000 -> 1.250.000
String miles(num v) => v.round().abs().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );

String moneda(dynamic valor) {
  final v = ((valor as num?) ?? 0).toDouble();
  return '${v < 0 ? '-' : ''}\$${miles(v)}';
}

String _dd(DateTime f) => f.day.toString().padLeft(2, '0');
String _mm(DateTime f) => f.month.toString().padLeft(2, '0');