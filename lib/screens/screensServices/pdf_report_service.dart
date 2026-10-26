import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../../db/database_helper.dart';
import 'report_analytics.dart';

class PdfReportService {
  // ---------- Paleta ----------
  static const _verde = PdfColor.fromInt(0xFF037C58);
  static const _verdeOscuro = PdfColor.fromInt(0xFF025A41);
  static const _verdeClaro = PdfColor.fromInt(0xFFE2F2ED);
  static const _rojo = PdfColor.fromInt(0xFFC62828);
  static const _naranja = PdfColor.fromInt(0xFFE59500);
  static const _naranjaOscuro = PdfColor.fromInt(0xFF9A5B00);
  static const _naranjaClaro = PdfColor.fromInt(0xFFFFF4E0);
  static const _texto = PdfColor.fromInt(0xFF1F2933);
  static const _gris = PdfColor.fromInt(0xFF6B7280);
  static const _borde = PdfColor.fromInt(0xFFE5E7EB);
  static const _fondo = PdfColor.fromInt(0xFFF8FAF9);

  // Fuente de títulos (ADLaM Display). El texto normal usa Kreon vía theme.
  static late pw.Font _fuenteTitulo;

  static Future<void> generarYCompartir({
    required DateTime inicio,
    required DateTime fin,
  }) async {
    final base = pw.Font.ttf(await rootBundle.load('assets/fonts/Kreon-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Kreon-Bold.ttf'));
    _fuenteTitulo = pw.Font.ttf(await rootBundle.load('assets/fonts/ADLaMDisplay-Regular.ttf'));

    final db = DatabaseHelper.instance;
    // El fin de rango se extiende hasta el final del día para incluir
    // todos los movimientos de esa fecha, no solo hasta medianoche.
    final finCompleto = DateTime(fin.year, fin.month, fin.day, 23, 59, 59);

    final resumen = await db.getResumenFinancieroPorRango(inicio, finCompleto);
    final ventasDiarias = await db.getVentasDiariasPorRango(inicio, finCompleto);
    final ventasPorHora = await db.getVentasPorHoraPorRango(inicio, finCompleto);
    final ranking = await db.getRankingProductosPorRango(inicio, finCompleto);

    final productosConStock = await db.getProductosConStockBatch();
    final stockBajo = await db.getProductosStockBajoActual();
    final sinVentas = await db.getProductosSinVentasRecientes(dias: 30);
    final bajaRotacion = await db.getMercanciaBajaRotacion(dias: 90);
    final valorInventario = await db.getValorInventarioActual();

    // ---- Contexto: cuántos días de datos reales respaldan el informe ----
    final primeraVenta = await db.getFechaPrimeraVenta();
    final ctx = ContextoPeriodo.calcular(
      inicio: inicio,
      fin: fin,
      primeraVenta: primeraVenta,
      diasConVentas: ventasDiarias.length,
    );

    // ---- Comparativo contra el periodo anterior (misma duración) ----
    final finAnteriorCompleto = DateTime(
      ctx.finAnterior.year,
      ctx.finAnterior.month,
      ctx.finAnterior.day,
      23,
      59,
      59,
    );
    final resumenPrevio = await db.getResumenFinancieroPorRango(ctx.inicioAnterior, finAnteriorCompleto);
    final comparativo = _Comparativo.calcular(resumen, resumenPrevio, ctx);

    // ---- Análisis ----
    final pareto = calcularPareto(ranking, ctx);
    final reposicion = calcularReposicion(
      productosConStock: productosConStock,
      ranking: ranking,
      ctx: ctx,
    );
    final numVentas = (resumen['numVentas'] as num?)?.toInt() ?? 0;
    final horasConfianza = evaluarHoras(numVentas: numVentas, ctx: ctx);

    final hayDatosLimitados = comparativo.confianza.baja ||
        (pareto?.confianza.baja ?? false) ||
        reposicion.confianza.baja ||
        (ventasPorHora.isNotEmpty && horasConfianza.baja);

    final lineasResumen = generarResumenEjecutivo(
      totalVentas: (resumen['totalVentas'] as num?)?.toDouble() ?? 0,
      ganancia: (resumen['gananciaBruta'] as num?)?.toDouble() ?? 0,
      variacionVentas: comparativo.ventas,
      comparativoConfiable: !comparativo.confianza.baja,
      ranking: ranking,
      pareto: pareto,
      reposicion: reposicion,
      bajaRotacion: bajaRotacion,
      hayDatosLimitados: hayDatosLimitados,
    );

    final hallazgos = _calcularHallazgos(
      ranking: ranking,
      bajaRotacion: bajaRotacion,
      stockBajo: stockBajo,
    );

    final doc = pw.Document();
    final fechaGeneracion = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: base, bold: bold),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
        // En la primera página va la portada, así que no se repite el encabezado.
        header: (c) => c.pageNumber == 1 ? pw.SizedBox() : _encabezado(inicio, fin),
        footer: _piePagina,
        build: (c) => [
          _portada(inicio, fin, fechaGeneracion),
          _resumenEjecutivo(lineasResumen),

          _seccion(
            '1',
            'Resumen del periodo',
            _seccionResumenPeriodo(resumen, ctx, comparativo),
          ),

          _seccion(
            '2',
            'Comportamiento de las ventas',
            _seccionVentas(ventasDiarias, ventasPorHora, inicio, fin, horasConfianza),
          ),

          _seccion('3', 'Productos destacados', _seccionRankings(ranking, pareto)),

          _seccion(
            '4',
            'Estado del inventario',
            _seccionInventario(
              stockBajo: stockBajo,
              sinVentas: sinVentas,
              bajaRotacion: bajaRotacion,
              valorInventario: valorInventario,
              reposicion: reposicion,
            ),
          ),

          _seccion('5', 'Hallazgos y oportunidades', _seccionHallazgos(hallazgos)),

          _notasInforme(ctx),
        ],
      ),
    );

    final directorio = await getApplicationDocumentsDirectory();
    final nombreArchivo = 'informe_negocio_${fechaGeneracion.millisecondsSinceEpoch}.pdf';
    final ruta = '${directorio.path}/$nombreArchivo';

    final bytes = await doc.save();
    await File(ruta).writeAsBytes(bytes);
    await Printing.sharePdf(bytes: bytes, filename: nombreArchivo);
  }

  // ===================================================================
  // PORTADA, RESUMEN EJECUTIVO Y ESTRUCTURA
  // ===================================================================

  static pw.Widget _portada(DateTime inicio, DateTime fin, DateTime generado) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: pw.BoxDecoration(
        color: _verde,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'INFORME DE NEGOCIO',
                style: const pw.TextStyle(fontSize: 8, color: _verdeClaro, letterSpacing: 1.6),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Resumen del negocio',
                style: pw.TextStyle(font: _fuenteTitulo, fontSize: 22, color: PdfColors.white),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: _verdeOscuro,
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Text(
                  '${_fechaDT(inicio)}  -  ${_fechaDT(fin)}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
                ),
              ),
            ],
          ),
          pw.Text(
            'Generado\n${_fechaHora(generado)}',
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(fontSize: 8, color: _verdeClaro, lineSpacing: 2),
          ),
        ],
      ),
    );
  }

  /// Frases clave armadas con reglas sobre los datos del periodo.
  static pw.Widget _resumenEjecutivo(List<LineaResumen> lineas) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 14),
      padding: const pw.EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: pw.BoxDecoration(
        color: _verdeClaro,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'LO MÁS IMPORTANTE',
            style: pw.TextStyle(
              fontSize: 7.5,
              color: _verdeOscuro,
              letterSpacing: 0.8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          for (final l in lineas)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 4),
                    width: 5,
                    height: 5,
                    decoration: pw.BoxDecoration(
                      color: l.alerta ? _naranja : _verde,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Text(
                      l.texto,
                      style: const pw.TextStyle(fontSize: 10, color: _texto, lineSpacing: 2),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Título + contenido en un mismo bloque: evita títulos huérfanos al final de página.
  static pw.Widget _seccion(String numero, String titulo, pw.Widget contenido) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 20,
                height: 20,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  color: _verde,
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Text(
                  numero,
                  style: pw.TextStyle(font: _fuenteTitulo, fontSize: 10, color: PdfColors.white),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                titulo,
                style: pw.TextStyle(font: _fuenteTitulo, fontSize: 13, color: _texto),
              ),
            ],
          ),
          pw.Divider(color: _borde, thickness: 0.8, height: 14),
          contenido,
        ],
      ),
    );
  }

  /// Tarjeta contenedora. Con [limitado] muestra la etiqueta "DATOS LIMITADOS".
  static pw.Widget _tarjeta(String titulo, pw.Widget hijo, {String? sub, bool limitado = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: limitado ? _naranja : _borde, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  titulo.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    color: _gris,
                    letterSpacing: 0.8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              if (limitado) _chip('DATOS LIMITADOS', _naranjaOscuro, _naranjaClaro),
            ],
          ),
          if (sub != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(sub, style: const pw.TextStyle(fontSize: 8, color: _gris, lineSpacing: 1.5)),
          ],
          pw.SizedBox(height: 8),
          hijo,
        ],
      ),
    );
  }

  /// Caja naranja que explica por qué un dato es poco confiable.
  /// No dibuja nada si el dato es confiable.
  static pw.Widget _aviso(Confianza c) {
    if (!c.baja) return pw.SizedBox();
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: pw.BoxDecoration(
        color: _naranjaClaro,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _naranja, width: 0.6),
      ),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: 'Datos limitados. ',
              style: pw.TextStyle(
                fontSize: 8.5,
                color: _naranjaOscuro,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.TextSpan(
              text: c.motivo ?? '',
              style: const pw.TextStyle(fontSize: 8.5, color: _texto, lineSpacing: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // ===================================================================
  // SECCIÓN 1: RESUMEN DEL PERIODO (con comparativo)
  // ===================================================================

  static pw.Widget _seccionResumenPeriodo(
    Map<String, dynamic> r,
    ContextoPeriodo ctx,
    _Comparativo comp,
  ) {
    final total = (r['totalVentas'] as num?)?.toDouble() ?? 0;
    final ganancia = (r['gananciaBruta'] as num?)?.toDouble() ?? 0;
    final numVentas = (r['numVentas'] as num?)?.toInt() ?? 0;
    final unidades = (r['unidadesVendidas'] as num?)?.toInt() ?? 0;
    final margen = total > 0 ? ganancia / total * 100 : 0.0;
    final promedioDiario = total / ctx.diasPeriodo;
    final limitada = comp.confianza.baja;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _kpi('Ventas totales', moneda(total), _verde,
                sub: '$numVentas registros de venta', vs: comp.ventas, limitada: limitada),
            pw.SizedBox(width: 8),
            _kpi('Ganancia bruta', moneda(ganancia), ganancia >= 0 ? _verde : _rojo,
                sub: 'Margen ${margen.toStringAsFixed(1).replaceAll('.', ',')}%',
                vs: comp.ganancia,
                limitada: limitada),
            pw.SizedBox(width: 8),
            _kpi('Promedio diario', moneda(promedioDiario), _texto,
                sub: 'en ${ctx.diasPeriodo} día(s)'),
            pw.SizedBox(width: 8),
            _kpi('Unidades vendidas', '$unidades', _texto,
                sub: 'en el periodo', vs: comp.unidades, limitada: limitada),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Comparado con el periodo anterior: ${_fechaDT(ctx.inicioAnterior)} - ${_fechaDT(ctx.finAnterior)}.',
          style: const pw.TextStyle(fontSize: 7.5, color: _gris),
        ),
        _aviso(comp.confianza),
      ],
    );
  }

  static pw.Widget _kpi(
    String titulo,
    String valor,
    PdfColor color, {
    String? sub,
    Variacion? vs,
    bool limitada = false,
  }) {
    PdfColor colorVs = _gris;
    if (vs != null && vs.disponible) {
      colorVs = limitada
          ? _naranjaOscuro
          : vs.sube
              ? _verde
              : vs.baja
                  ? _rojo
                  : _gris;
    }

    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: pw.BoxDecoration(
          color: _fondo,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: _borde, width: 0.8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              titulo.toUpperCase(),
              style: const pw.TextStyle(fontSize: 7, color: _gris, letterSpacing: 0.6),
            ),
            pw.SizedBox(height: 6),
            pw.Text(valor, style: pw.TextStyle(font: _fuenteTitulo, fontSize: 15, color: color)),
            if (sub != null) ...[
              pw.SizedBox(height: 3),
              pw.Text(sub, style: const pw.TextStyle(fontSize: 7.5, color: _gris)),
            ],
            if (vs != null) ...[
              pw.SizedBox(height: 3),
              pw.Text(
                vs.disponible
                    ? '${vs.texto} vs. anterior${limitada ? ' *' : ''}'
                    : 'sin datos previos',
                style: pw.TextStyle(fontSize: 7.5, color: colorVs, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===================================================================
  // SECCIÓN 2: COMPORTAMIENTO DE LAS VENTAS
  // ===================================================================

  static pw.Widget _seccionVentas(
    List<Map<String, dynamic>> ventasDiarias,
    List<Map<String, dynamic>> ventasPorHora,
    DateTime inicio,
    DateTime fin,
    Confianza horasConfianza,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _tarjeta('Evolución de ventas diarias', _graficoDiario(ventasDiarias, inicio, fin)),
        if (ventasDiarias.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _tarjeta('Mejores días', _listaMejoresDias(ventasDiarias))),
              if (ventasPorHora.isNotEmpty) ...[
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _tarjeta(
                    'Horas de mayor actividad',
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [_listaHoras(ventasPorHora), _aviso(horasConfianza)],
                    ),
                    limitado: horasConfianza.baja,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  static String _clave(DateTime f) => '${f.year}-${f.month}-${f.day}';

  /// Gráfico con TODOS los días del periodo (los días sin ventas aparecen en cero),
  /// así la escala horizontal es real y no engaña al comparar fechas.
  static pw.Widget _graficoDiario(
    List<Map<String, dynamic>> ventas,
    DateTime inicio,
    DateTime fin,
  ) {
    if (ventas.isEmpty) {
      return pw.Text(
        'No hay ventas registradas en este periodo.',
        style: const pw.TextStyle(fontSize: 10, color: _gris),
      );
    }

    final porDia = <String, double>{};
    for (final d in ventas) {
      final f = DateTime.parse(d['dia'] as String);
      porDia[_clave(f)] = (porDia[_clave(f)] ?? 0) + (d['valor'] as num).toDouble();
    }

    final dias = <DateTime>[];
    final ini = DateTime(inicio.year, inicio.month, inicio.day);
    final fi = DateTime(fin.year, fin.month, fin.day);
    for (var f = ini; !f.isAfter(fi); f = DateTime(f.year, f.month, f.day + 1)) {
      dias.add(f);
    }

    final valores = dias.map((f) => porDia[_clave(f)] ?? 0.0).toList();
    final maxValor = valores.fold<double>(0, (a, b) => b > a ? b : a);
    final totalPeriodo = valores.fold<double>(0, (a, b) => a + b);
    final idxMejor = valores.indexOf(maxValor);

    const alto = 110.0;
    final paso = math.max(1, (dias.length / 6).ceil());
    final separacion = dias.length > 45 ? 0.3 : 1.0;

    pw.Widget etiquetaY(double v) =>
        pw.Text(_compacta(v), style: const pw.TextStyle(fontSize: 7, color: _gris));
    pw.Widget guia() => pw.Container(height: 0.5, color: _borde);

    final concentracion = totalPeriodo > 0 ? maxValor / totalPeriodo : 0.0;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 34,
              height: alto,
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [etiquetaY(maxValor), etiquetaY(maxValor / 2), etiquetaY(0)],
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.SizedBox(
                    height: alto,
                    child: pw.Stack(
                      fit: pw.StackFit.expand,
                      children: [
                        pw.Positioned(top: 0, left: 0, right: 0, child: guia()),
                        pw.Positioned(top: alto / 2, left: 0, right: 0, child: guia()),
                        pw.Positioned(bottom: 0, left: 0, right: 0, child: guia()),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < valores.length; i++)
                              pw.Expanded(
                                child: pw.Padding(
                                  padding: pw.EdgeInsets.symmetric(horizontal: separacion),
                                  child: valores[i] <= 0
                                      ? pw.SizedBox()
                                      : pw.Container(
                                          height: math.max(2, valores[i] / maxValor * alto),
                                          decoration: pw.BoxDecoration(
                                            color: i == idxMejor ? _verdeOscuro : _verde,
                                            borderRadius: const pw.BorderRadius.only(
                                              topLeft: pw.Radius.circular(2),
                                              topRight: pw.Radius.circular(2),
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      for (var i = 0; i < dias.length; i++)
                        pw.Expanded(
                          child: pw.Text(
                            i % paso == 0 ? _fechaCorta(dias[i]) : '',
                            softWrap: false,
                            overflow: pw.TextOverflow.visible,
                            style: const pw.TextStyle(fontSize: 7, color: _gris),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (concentracion >= 0.6) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            'El ${_fechaCorta(dias[idxMejor])} concentra el ${(concentracion * 100).round()}% de las ventas del periodo.',
            style: pw.TextStyle(fontSize: 8, color: _gris, fontStyle: pw.FontStyle.italic),
          ),
        ],
      ],
    );
  }

  static pw.Widget _listaMejoresDias(List<Map<String, dynamic>> ventas) {
    final ordenados = [...ventas]
      ..sort((a, b) => (b['valor'] as num).compareTo(a['valor'] as num));
    final top = ordenados.take(3).toList();
    final maxV = (top.first['valor'] as num).toDouble();

    return pw.Column(
      children: [
        for (var i = 0; i < top.length; i++)
          _filaRanking(
            posicion: i + 1,
            etiqueta: _fechaCorta(DateTime.parse(top[i]['dia'] as String)),
            valorTexto: moneda(top[i]['valor']),
            valor: (top[i]['valor'] as num).toDouble(),
            maxValor: maxV,
            color: _verde,
            maxChars: 20,
          ),
      ],
    );
  }

  static pw.Widget _listaHoras(List<Map<String, dynamic>> ventasPorHora) {
    final top = ventasPorHora.take(5).toList();
    final maxU = (top.first['unidades'] as num).toDouble();

    return pw.Column(
      children: [
        for (var i = 0; i < top.length; i++)
          _filaRanking(
            posicion: i + 1,
            etiqueta: '${(top[i]['hora'] as int).toString().padLeft(2, '0')}:00',
            valorTexto: '${(top[i]['unidades'] as num).toInt()} unid.',
            valor: (top[i]['unidades'] as num).toDouble(),
            maxValor: maxU,
            color: _naranja,
            maxChars: 20,
          ),
      ],
    );
  }

  // ===================================================================
  // SECCIÓN 3: PRODUCTOS DESTACADOS + PARETO
  // ===================================================================

  static pw.Widget _seccionRankings(List<Map<String, dynamic>> ranking, ResultadoPareto? pareto) {
    if (ranking.isEmpty) {
      return pw.Text(
        'No hay ventas registradas en este periodo.',
        style: const pw.TextStyle(fontSize: 10, color: _gris),
      );
    }

    List<Map<String, dynamic>> ordenar(String campo) => [...ranking]
      ..sort((a, b) => (b[campo] as num).compareTo(a[campo] as num));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _subRanking('Más vendidos', ordenar('unidadesVendidas'), 'unidadesVendidas',
                  (p) => '${(p['unidadesVendidas'] as num).toInt()} unid.', _verde),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _subRanking('Mayores ingresos', ordenar('ingresoTotal'), 'ingresoTotal',
                  (p) => moneda(p['ingresoTotal']), _naranja),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _subRanking('Mayor ganancia', ordenar('gananciaEstimada'), 'gananciaEstimada',
                  (p) => moneda(p['gananciaEstimada']), _verde),
            ),
          ],
        ),
        if (pareto != null) ...[
          pw.SizedBox(height: 10),
          _tarjetaPareto(pareto),
        ],
      ],
    );
  }

  static pw.Widget _subRanking(
    String titulo,
    List<Map<String, dynamic>> lista,
    String campo,
    String Function(Map<String, dynamic>) formatear,
    PdfColor color,
  ) {
    final top5 = lista.take(5).toList();
    final maxV = (top5.first[campo] as num).toDouble().abs();

    return _tarjeta(
      titulo,
      pw.Column(
        children: [
          for (var i = 0; i < top5.length; i++)
            _filaRanking(
              posicion: i + 1,
              etiqueta: top5[i]['nombre'] as String,
              valorTexto: formatear(top5[i]),
              valor: (top5[i][campo] as num).toDouble().abs(),
              maxValor: maxV,
              color: color,
              maxChars: 13,
            ),
        ],
      ),
    );
  }

  static pw.Widget _tarjetaPareto(ResultadoPareto p) {
    final mostrar = p.principales.take(8).toList();
    final maxPct = mostrar.first.porcentaje;

    return _tarjeta(
      'Concentración de ventas (Pareto)',
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${p.cuantosHacen80} de ${p.totalProductos} producto(s) generan el 80% de tus ingresos.',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _texto),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Participación de cada producto en el ingreso total y porcentaje acumulado.',
            style: const pw.TextStyle(fontSize: 8, color: _gris),
          ),
          pw.SizedBox(height: 6),
          for (var i = 0; i < mostrar.length; i++)
            _filaRanking(
              posicion: i + 1,
              etiqueta: mostrar[i].nombre,
              valorTexto: '${_pct(mostrar[i].porcentaje)}  (acum. ${_pct(mostrar[i].acumulado)})',
              valor: mostrar[i].porcentaje,
              maxValor: maxPct,
              color: _verde,
              maxChars: 40,
            ),
          if (p.principales.length > mostrar.length)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                '+ ${p.principales.length - mostrar.length} producto(s) más hasta llegar al 80%.',
                style: const pw.TextStyle(fontSize: 8, color: _gris),
              ),
            ),
          _aviso(p.confianza),
        ],
      ),
      limitado: p.confianza.baja,
    );
  }

  // ===================================================================
  // SECCIÓN 4: ESTADO DEL INVENTARIO + REPOSICIÓN
  // ===================================================================

  static pw.Widget _seccionInventario({
    required List<Map<String, dynamic>> stockBajo,
    required List<Map<String, dynamic>> sinVentas,
    required List<Map<String, dynamic>> bajaRotacion,
    required double valorInventario,
    required ResultadoReposicion reposicion,
  }) {
    final valorBajaRotacion = bajaRotacion.fold<double>(
      0,
      (t, f) => t + (f['valorInmovilizado'] as num).toDouble(),
    );

    final inmovilizados = [...bajaRotacion]
      ..sort((a, b) => (b['valorInmovilizado'] as num).compareTo(a['valorInmovilizado'] as num));
    final topInmov = inmovilizados.take(5).toList();
    final maxInmov = topInmov.isEmpty ? 1.0 : (topInmov.first['valorInmovilizado'] as num).toDouble();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _kpi('Valor del inventario', moneda(valorInventario), _verde),
            pw.SizedBox(width: 8),
            _kpi('Stock bajo', '${stockBajo.length}', stockBajo.isEmpty ? _verde : _rojo,
                sub: 'productos'),
            pw.SizedBox(width: 8),
            _kpi('Sin ventas (30 d)', '${sinVentas.length}', sinVentas.isEmpty ? _verde : _naranja,
                sub: 'productos'),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _tarjeta(
                'Productos con poco stock',
                stockBajo.isEmpty
                    ? pw.Text(
                        'Todos los productos están por encima de su stock mínimo.',
                        style: const pw.TextStyle(fontSize: 9, color: _verde, lineSpacing: 2),
                      )
                    : pw.Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: stockBajo.take(10).map((p) {
                          return _chip(
                            '${p['nombre']} (${(p['stockActual'] as num).toInt()})',
                            _rojo,
                            PdfColors.red50,
                          );
                        }).toList(),
                      ),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: _tarjeta(
                'Mercancía sin ventas (90 d)',
                topInmov.isEmpty
                    ? pw.Text(
                        'No hay mercancía inmovilizada.',
                        style: const pw.TextStyle(fontSize: 9, color: _verde),
                      )
                    : pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < topInmov.length; i++)
                            _filaRanking(
                              posicion: i + 1,
                              etiqueta: topInmov[i]['nombre'] as String,
                              valorTexto: moneda(topInmov[i]['valorInmovilizado']),
                              valor: (topInmov[i]['valorInmovilizado'] as num).toDouble(),
                              maxValor: maxInmov == 0 ? 1 : maxInmov,
                              color: _naranja,
                              maxChars: 16,
                            ),
                          pw.SizedBox(height: 6),
                          pw.Text(
                            'Total inmovilizado: ${moneda(valorBajaRotacion)}',
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              fontWeight: pw.FontWeight.bold,
                              color: _naranjaOscuro,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        _tarjetaReposicion(reposicion),
      ],
    );
  }

  static pw.Widget _tarjetaReposicion(ResultadoReposicion r) {
    const maxFilas = 8;
    final mostrar = r.filas.take(maxFilas).toList();
    final hayDebiles = mostrar.any((f) => f.debil);

    pw.Widget celda(
      String t, {
      int flex = 2,
      bool encabezado = false,
      pw.TextAlign align = pw.TextAlign.right,
      PdfColor color = _texto,
      bool negrita = false,
    }) {
      return pw.Expanded(
        flex: flex,
        child: pw.Text(
          t,
          textAlign: align,
          style: encabezado
              ? const pw.TextStyle(fontSize: 7, color: _gris, letterSpacing: 0.5)
              : pw.TextStyle(
                  fontSize: 8.5,
                  color: color,
                  fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
        ),
      );
    }

    final pw.Widget contenido;
    if (mostrar.isEmpty) {
      contenido = pw.Text(
        'Ningún producto se agotaría en los próximos ${Umbrales.diasObjetivoStock} días al ritmo de ventas del periodo.',
        style: const pw.TextStyle(fontSize: 9, color: _verde, lineSpacing: 2),
      );
    } else {
      contenido = pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _borde, width: 0.8)),
            ),
            child: pw.Row(
              children: [
                celda('PRODUCTO', flex: 4, encabezado: true, align: pw.TextAlign.left),
                celda('STOCK', encabezado: true),
                celda('CONSUMO/DÍA', encabezado: true),
                celda('SE AGOTA EN', encabezado: true),
                celda('SUGERIDO', encabezado: true),
              ],
            ),
          ),
          for (final f in mostrar)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 5),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: _borde, width: 0.4)),
              ),
              child: pw.Row(
                children: [
                  celda('${_cortar(f.nombre, 24)}${f.debil ? ' *' : ''}',
                      flex: 4, align: pw.TextAlign.left),
                  celda('${f.stock}'),
                  celda(f.consumoDiario.toStringAsFixed(1).replaceAll('.', ',')),
                  celda(
                    _textoDias(f.diasRestantes),
                    negrita: true,
                    color: f.diasRestantes <= 3
                        ? _rojo
                        : f.diasRestantes <= 7
                            ? _naranjaOscuro
                            : _texto,
                  ),
                  celda(f.sugerido > 0 ? '${f.sugerido} ${f.unidad}' : '-'),
                ],
              ),
            ),
          if (r.filas.length > maxFilas)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                '+ ${r.filas.length - maxFilas} producto(s) más.',
                style: const pw.TextStyle(fontSize: 8, color: _gris),
              ),
            ),
          if (hayDebiles)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                '* Se vendieron muy pocas unidades (menos de ${Umbrales.unidadesMinProducto}): estimación débil.',
                style: const pw.TextStyle(fontSize: 8, color: _gris),
              ),
            ),
        ],
      );
    }

    return _tarjeta(
      'Reposición sugerida',
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          contenido,
          if (r.bajoSinVentas.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text(
                'Con stock bajo pero sin ventas en el periodo (no se puede estimar cuándo se agotan): '
                '${r.bajoSinVentas.take(6).join(', ')}.',
                style: const pw.TextStyle(fontSize: 8, color: _gris, lineSpacing: 1.5),
              ),
            ),
          _aviso(r.confianza),
        ],
      ),
      sub: 'Productos que se agotarían en ${Umbrales.diasObjetivoStock} días o menos, o que ya están bajo su mínimo. '
          'El sugerido cubre ${Umbrales.diasObjetivoStock} días de ventas.',
      limitado: r.confianza.baja,
    );
  }

  static String _textoDias(double d) {
    if (d < 1) return '< 1 día';
    final n = d.floor();
    return n == 1 ? '1 día' : '$n días';
  }

  static pw.Widget _chip(String texto, PdfColor color, PdfColor fondo) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(color: fondo, borderRadius: pw.BorderRadius.circular(10)),
      child: pw.Text(texto, style: pw.TextStyle(fontSize: 7.5, color: color)),
    );
  }

  // ===================================================================
  // SECCIÓN 5: HALLAZGOS
  // ===================================================================

  static List<_Hallazgo> _calcularHallazgos({
    required List<Map<String, dynamic>> ranking,
    required List<Map<String, dynamic>> bajaRotacion,
    required List<Map<String, dynamic>> stockBajo,
  }) {
    // --- Mejor resultado: producto con mayor ganancia estimada del periodo ---
    _Hallazgo mejorResultado;
    if (ranking.isNotEmpty) {
      final top = [...ranking]
        ..sort((a, b) => (b['gananciaEstimada'] as num).compareTo(a['gananciaEstimada'] as num));
      final p = top.first;
      mejorResultado = _Hallazgo(
        titulo: 'Mejor resultado',
        texto:
            '${p['nombre']} fue el producto más rentable del periodo, con una ganancia estimada de ${moneda(p['gananciaEstimada'])}.',
        color: _verde,
      );
    } else {
      mejorResultado = _Hallazgo(
        titulo: 'Mejor resultado',
        texto: 'Aún no hay suficientes ventas en este periodo para identificar un producto destacado.',
        color: _verde,
      );
    }

    // --- Problema principal y Oportunidad: misma lista de prioridad, sin repetir ---
    final candidatos = <_Hallazgo>[];

    if (bajaRotacion.isNotEmpty) {
      final peor = [...bajaRotacion]
        ..sort((a, b) => (b['valorInmovilizado'] as num).compareTo(a['valorInmovilizado'] as num));
      final p = peor.first;
      candidatos.add(_Hallazgo(
        titulo: '',
        texto:
            'Tienes ${moneda(p['valorInmovilizado'])} inmovilizados en "${p['nombre']}", sin ventas en los últimos 90 días.',
        color: _naranja,
      ));
    }

    if (stockBajo.isNotEmpty) {
      candidatos.add(_Hallazgo(
        titulo: '',
        texto: '${stockBajo.length} producto(s) están por debajo de su stock mínimo y podrían agotarse pronto.',
        color: _rojo,
      ));
    }

    if (candidatos.isEmpty) {
      candidatos.add(_Hallazgo(
        titulo: '',
        texto: 'No se detectaron problemas destacables en el inventario durante este periodo.',
        color: _gris,
      ));
    }

    final problemaPrincipal = _Hallazgo(
      titulo: 'Principal problema',
      texto: candidatos[0].texto,
      color: candidatos[0].color,
    );

    final oportunidad = candidatos.length > 1
        ? _Hallazgo(
            titulo: 'Oportunidad de mejora',
            texto: candidatos[1].texto,
            color: candidatos[1].color,
          )
        : _Hallazgo(
            titulo: 'Oportunidad de mejora',
            texto: ranking.isNotEmpty
                ? 'Revisa si puedes aumentar el precio o promocionar más tus productos de mayor ganancia para crecer el margen del negocio.'
                : 'Registra más ventas en la app para empezar a recibir recomendaciones personalizadas.',
            color: _verde,
          );

    return [mejorResultado, problemaPrincipal, oportunidad];
  }

  static pw.Widget _seccionHallazgos(List<_Hallazgo> hallazgos) {
    return pw.Column(
      children: hallazgos.map((h) {
        return pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.fromLTRB(14, 10, 12, 10),
          decoration: pw.BoxDecoration(
            color: _fondo,
            border: pw.Border(left: pw.BorderSide(color: h.color, width: 3)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                h.titulo.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: h.color,
                  letterSpacing: 0.8,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(h.texto, style: const pw.TextStyle(fontSize: 10, color: _texto, lineSpacing: 2)),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Explica cómo se calculan las cifras y cuándo se marca "datos limitados".
  static pw.Widget _notasInforme(ContextoPeriodo ctx) {
    pw.Widget linea(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text(t, style: const pw.TextStyle(fontSize: 8, color: _gris, lineSpacing: 1.5)),
        );

    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 18),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _fondo,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _borde, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'CÓMO LEER ESTE INFORME',
            style: pw.TextStyle(
              fontSize: 7.5,
              color: _gris,
              letterSpacing: 0.8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          linea('Este informe se apoya en ${ctx.diasConHistorial} día(s) con historial de ventas dentro del periodo, '
              'con ventas en ${ctx.diasConVentas} de ellos.'),
          linea('Un "registro de venta" es cada salida de producto guardada en la app; una compra de varios productos '
              'genera varios registros.'),
          linea('Comparativo: se compara contra el periodo anterior de igual duración. Se marca como limitado si el periodo '
              'tiene menos de ${Umbrales.diasComparativo} días, si el anterior no tuvo ventas o si tu historial empieza a mitad de él.'),
          linea('Reposición: consumo diario = unidades vendidas / días con historial. Se marca como limitado con menos de '
              '${Umbrales.diasReposicion} días de historial.'),
          linea('Pareto: se marca como limitado con menos de ${Umbrales.diasPareto} días de historial o menos de '
              '${Umbrales.productosPareto} productos con ventas.'),
          linea('Horas de actividad: se marca como limitado con menos de ${Umbrales.registrosHoras} registros de venta.'),
          linea('Ganancia = ventas - costo de los lotes vendidos (método PEPS). No incluye pérdidas por diferencias de inventario.'),
        ],
      ),
    );
  }

  // ===================================================================
  // HELPERS
  // ===================================================================

  /// Fila compacta: insignia con posición, nombre, valor y barra fina debajo.
  static pw.Widget _filaRanking({
    required int posicion,
    required String etiqueta,
    required String valorTexto,
    required double valor,
    required double maxValor,
    required PdfColor color,
    int maxChars = 16,
  }) {
    final fraccion = maxValor > 0 ? (valor / maxValor).clamp(0.03, 1.0) : 0.03;
    final flexLleno = (fraccion * 1000).round().clamp(30, 1000);
    final flexVacio = 1000 - flexLleno;

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 12,
                height: 12,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  color: posicion == 1 ? color : _borde,
                  shape: pw.BoxShape.circle,
                ),
                child: pw.Text(
                  '$posicion',
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                    color: posicion == 1 ? PdfColors.white : _gris,
                  ),
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: pw.Text(
                  _cortar(etiqueta, maxChars),
                  maxLines: 1,
                  style: const pw.TextStyle(fontSize: 8.5, color: _texto),
                ),
              ),
              pw.Text(
                valorTexto,
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _texto),
              ),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Container(
            height: 4,
            decoration: pw.BoxDecoration(color: _borde, borderRadius: pw.BorderRadius.circular(2)),
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: flexLleno,
                  child: pw.Container(
                    decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(2)),
                  ),
                ),
                if (flexVacio > 0) pw.Expanded(flex: flexVacio, child: pw.SizedBox()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _encabezado(DateTime inicio, DateTime fin) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.8, color: _borde)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Informe de Negocio',
              style: pw.TextStyle(font: _fuenteTitulo, fontSize: 9, color: _verde)),
          pw.Text('${_fechaDT(inicio)}  -  ${_fechaDT(fin)}',
              style: const pw.TextStyle(fontSize: 8.5, color: _gris)),
        ],
      ),
    );
  }

  static pw.Widget _piePagina(pw.Context c) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(width: 0.8, color: _borde)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Inventario para tu negocio', style: const pw.TextStyle(fontSize: 8, color: _gris)),
          pw.Text('Página ${c.pageNumber} de ${c.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _gris)),
        ],
      ),
    );
  }

  // ---------- Formatos ----------

  static String _cortar(String s, int max) => s.length > max ? '${s.substring(0, max - 1)}…' : s;

  static String _pct(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')}%';

  /// Para el eje Y: 441300 -> $441K, 2500000 -> $2,5M
  static String _compacta(double v) {
    if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(1).replaceAll('.', ',')}M';
    if (v >= 1e3) return '\$${(v / 1e3).round()}K';
    return '\$${v.round()}';
  }

  static String _fechaHora(DateTime f) =>
      '${_fechaDT(f)} ${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

  static String _fechaDT(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  static String _fechaCorta(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}';
}

class _Hallazgo {
  final String titulo;
  final String texto;
  final PdfColor color;
  _Hallazgo({required this.titulo, required this.texto, required this.color});
}

/// Variaciones del periodo actual contra el anterior + su nivel de confianza.
class _Comparativo {
  final Variacion ventas;
  final Variacion ganancia;
  final Variacion unidades;
  final Confianza confianza;

  _Comparativo(this.ventas, this.ganancia, this.unidades, this.confianza);

  factory _Comparativo.calcular(
    Map<String, dynamic> actual,
    Map<String, dynamic> previo,
    ContextoPeriodo ctx,
  ) {
    double n(Map<String, dynamic> m, String k) => (m[k] as num?)?.toDouble() ?? 0;

    final ventasPrevias = n(previo, 'totalVentas');
    return _Comparativo(
      variacion(n(actual, 'totalVentas'), ventasPrevias),
      variacion(n(actual, 'gananciaBruta'), n(previo, 'gananciaBruta')),
      variacion(n(actual, 'unidadesVendidas'), n(previo, 'unidadesVendidas')),
      evaluarComparativo(ctx: ctx, ventasPrevias: ventasPrevias),
    );
  }
}