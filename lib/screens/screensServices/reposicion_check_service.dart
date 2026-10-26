import 'package:shared_preferences/shared_preferences.dart';
import '../../db/database_helper.dart';
import 'notificacion_service.dart';
import 'report_analytics.dart';

class ReposicionCheckService {
  static const _diasVentana = 30;
  static const _umbralDiasRestantes = 7;

  static String _clavePorProducto(int productoId) => 'reposicion_notif_${productoId}_dia';

  static Future<bool> _yaNotificadoHoy(SharedPreferences prefs, int productoId, String hoyStr) {
    return Future.value(prefs.getString(_clavePorProducto(productoId)) == hoyStr);
  }

  static Future<void> _marcarNotificadoHoy(SharedPreferences prefs, int productoId, String hoyStr) {
    return prefs.setString(_clavePorProducto(productoId), hoyStr);
  }

  /// Calcula el contexto compartido (días con historial) que necesita
  /// cualquier evaluación de reposición, sin importar si es para todo
  /// el catálogo o para un solo producto.
  static Future<ContextoPeriodo> _construirContexto(DateTime hoy, DateTime inicio, DateTime finCompleto) async {
    final db = DatabaseHelper.instance;
    final ventasDiarias = await db.getVentasDiariasPorRango(inicio, finCompleto);
    final primeraVenta = await db.getFechaPrimeraVenta();
    return ContextoPeriodo.calcular(
      inicio: inicio,
      fin: hoy,
      primeraVenta: primeraVenta,
      diasConVentas: ventasDiarias.length,
    );
  }

  /// Revisión del CATÁLOGO COMPLETO — pensada para correr una vez al
  /// día al abrir la app. Es la red de seguridad: captura productos
  /// que se vuelven urgentes sin que haya mediado una venta hoy (por
  /// ejemplo, una pérdida registrada en Diferencias de inventario, o
  /// simplemente el paso del tiempo).
  static Future<void> verificarCatalogoCompleto() async {
    try {
      final db = DatabaseHelper.instance;
      final prefs = await SharedPreferences.getInstance();
      final hoy = DateTime.now();
      final hoyStr = '${hoy.year}-${hoy.month}-${hoy.day}';
      final inicio = hoy.subtract(const Duration(days: _diasVentana));
      final finCompleto = DateTime(hoy.year, hoy.month, hoy.day, 23, 59, 59);

      final ctx = await _construirContexto(hoy, inicio, finCompleto);

      final productosConStock = await db.getProductosConStockBatch();
      final ranking = await db.getRankingProductosPorRango(inicio, finCompleto);
      final unidadesPorId = <int, double>{
        for (final r in ranking) (r['id'] as num).toInt(): (r['unidadesVendidas'] as num?)?.toDouble() ?? 0,
      };

      for (final p in productosConStock) {
        if ((p['activo'] as num?)?.toInt() != 1) continue;
        final id = (p['id'] as num).toInt();

        if (await _yaNotificadoHoy(prefs, id, hoyStr)) continue; // ya avisado hoy por otra vía

        final fila = evaluarFilaReposicion(
          nombre: p['nombre'] as String,
          unidad: (p['unidad'] as String?) ?? '',
          stock: (p['stockActual'] as num).toInt(),
          stockMinimo: p['stockMinimo'] as int,
          unidadesVendidas: unidadesPorId[id] ?? 0,
          diasHistorial: ctx.diasConHistorial,
        );

        if (fila == null || fila.debil) continue;
        if (fila.diasRestantes > _umbralDiasRestantes) continue;
        if (ctx.diasConHistorial < Umbrales.diasReposicion) continue; // poco historial global: no arriesgar

        await NotificacionService.instance.mostrarAlertaReposicion(
          productoId: id,
          nombreProducto: fila.nombre,
          diasRestantes: fila.diasRestantes,
          sugerido: fila.sugerido,
          unidad: fila.unidad,
        );
        await _marcarNotificadoHoy(prefs, id, hoyStr);
      }
    } catch (_) {
      // Silencioso a propósito: un fallo aquí no debe interrumpir el arranque de la app.
    }
  }

  /// Revisión de UN SOLO PRODUCTO — pensada para correr justo después
  /// de registrar una venta exitosa. Mucho más liviana que la revisión
  /// completa (no recorre todo el catálogo), y da el aviso en el
  /// momento más relevante: justo cuando esa venta empujó al producto
  /// bajo el umbral.
  static Future<void> verificarProducto(int productoId) async {
    try {
      final db = DatabaseHelper.instance;
      final prefs = await SharedPreferences.getInstance();
      final hoy = DateTime.now();
      final hoyStr = '${hoy.year}-${hoy.month}-${hoy.day}';

      if (await _yaNotificadoHoy(prefs, productoId, hoyStr)) {
        return;
      }

      final producto = await db.getProducto(productoId);
      if (producto == null || !producto.activo) {
        return;
      }

      final inicio = hoy.subtract(const Duration(days: _diasVentana));
      final finCompleto = DateTime(hoy.year, hoy.month, hoy.day, 23, 59, 59);

      final ctx = await _construirContexto(hoy, inicio, finCompleto);
      
      if (ctx.diasConHistorial < Umbrales.diasReposicion) {
        return;
      }

      final stock = await db.getStockActual(productoId);
      final unidades = await db.getUnidadesVendidasProducto(productoId, inicio, finCompleto);
      
      final fila = evaluarFilaReposicion(
        nombre: producto.nombre,
        unidad: producto.unidad,
        stock: stock,
        stockMinimo: producto.stockMinimo,
        unidadesVendidas: unidades,
        diasHistorial: ctx.diasConHistorial,
      );

      if (fila == null) {
        return;
      }
      if (fila.debil) {
      
        return;
      }
      if (fila.diasRestantes > _umbralDiasRestantes) {
        return;
      }

      
      await NotificacionService.instance.mostrarAlertaReposicion(
        productoId: productoId,
        nombreProducto: fila.nombre,
        diasRestantes: fila.diasRestantes,
        sugerido: fila.sugerido,
        unidad: fila.unidad,
      );
      await _marcarNotificadoHoy(prefs, productoId, hoyStr);
    } catch (e) {
      // ignore: avoid_print
      print('[Reposicion] ERROR: $e');
    }
  }

  /// SOLO PARA PRUEBAS: limpia el throttle de un producto específico
  /// (o de todos, si no se indica ninguno) para poder re-probar sin
  /// esperar al día siguiente.
  static Future<void> forzarVerificacion({int? productoId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (productoId != null) {
      await prefs.remove(_clavePorProducto(productoId));
      await verificarProducto(productoId);
    } else {
      final keys = prefs.getKeys().where((k) => k.startsWith('reposicion_notif_'));
      for (final k in keys) {
        await prefs.remove(k);
      }
      await verificarCatalogoCompleto();
    }
  }
}