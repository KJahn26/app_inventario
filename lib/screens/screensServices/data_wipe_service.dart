import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../db/database_helper.dart';
import 'export_service.dart';

enum ResultadoBorrado { exitoso, exportacionNoCompletada }

/// Borra todos los datos de la app, pero solo después de confirmar
/// que el usuario realmente guardó o compartió un respaldo completo.
/// Si el panel de compartir se cierra sin acción, no se borra nada.
class DataWipeService {
  static Future<ResultadoBorrado> exportarYBorrarTodo() async {
    final estado = await ExportService.exportarYCompartir();

    if (estado != ShareResultStatus.success) {
      return ResultadoBorrado.exportacionNoCompletada;
    }

    await DatabaseHelper.instance.resetearBaseDeDatos();

    // Limpia también el throttle de notificaciones de reposición,
    // para que no quede referenciando productos que ya no existen.
    final prefs = await SharedPreferences.getInstance();
    final claves = prefs.getKeys().where((k) => k.startsWith('reposicion_'));
    for (final k in claves) {
      await prefs.remove(k);
    }

    return ResultadoBorrado.exitoso;
  }
}