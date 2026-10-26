import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Dispara notificaciones locales del sistema operativo (sin
/// depender de internet ni de un servidor push) para alertar sobre
/// stock bajo.
///
/// Implementado como singleton ([instance]) porque solo debe existir
/// una inicialización del plugin por toda la vida de la app — ver
/// [inicializar].
class NotificacionService {
  static final NotificacionService instance = NotificacionService._internal();
  NotificacionService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _inicializado = false;

  /// Configura el plugin de notificaciones y solicita el permiso de
  /// notificaciones explícito que exige Android 13+.
  ///
  /// Debe llamarse una vez al arrancar la app (en `main()`, antes de
  /// `runApp`), no en cada pantalla. El flag [_inicializado] evita
  /// reinicializar el plugin si por error se llama más de una vez.
  Future<void> inicializar() async {
    if (_inicializado) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings);

     // Pide permiso explícito en Android 13+
     await _plugin
         .resolvePlatformSpecificImplementation
             <AndroidFlutterLocalNotificationsPlugin>()
         ?.requestNotificationsPermission();

     _inicializado = true;
   }

  /// Muestra una notificación de stock bajo para un producto.
  ///
  /// Se usa [productoId] como id de la notificación (en vez de un id
  /// autoincremental) a propósito: si el mismo producto vuelve a
  /// quedar bajo el mínimo más adelante, Android reemplaza la
  /// notificación existente en vez de apilar una nueva, evitando que
  /// la barra de notificaciones se llene de alertas repetidas del
  /// mismo producto.
  Future<void> mostrarAlertaStockBajo({
    required int productoId,
    required String nombreProducto,
    required int stockActual,
    required String unidad,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'stock_bajo_channel',
      'Alertas de stock bajo',
      channelDescription: 'Notifica cuando un producto baja del stock mínimo',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      productoId, // usamos el id del producto como id de notificación (evita duplicados por producto)
      'Stock bajo: $nombreProducto',
      'Quedan $stockActual $unidad. Es momento de reponer.',
      details,
    );
  }

  /// Notifica que un producto se agotaría pronto al ritmo de venta
  /// actual (reposición proactiva), a diferencia de
  /// [mostrarAlertaStockBajo] que avisa cuando YA está bajo el mínimo.
  ///
  /// Usa un id de notificación distinto (desplazado +100000 respecto
  /// al id del producto) para no pisar la notificación de stock bajo
  /// del mismo producto si ambas aplican a la vez.
  Future<void> mostrarAlertaReposicion({
    required int productoId,
    required String nombreProducto,
    required double diasRestantes,
    required int sugerido,
    required String unidad,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'reposicion_channel',
      'Sugerencias de reposición',
      channelDescription: 'Avisa cuando un producto se agotaría pronto al ritmo de venta actual',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    final dias = diasRestantes < 1 ? 'menos de 1 día' : '${diasRestantes.floor()} día(s)';

    await _plugin.show(
      100000 + productoId,
      'Repón pronto: $nombreProducto',
      'Se agotaría en $dias al ritmo actual. Sugerido: $sugerido $unidad.',
      details,
    );
  }
}