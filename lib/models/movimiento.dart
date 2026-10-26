enum TipoMovimiento { entrada, salida, perdida, ganancia }

/// Registra cada entrada o salida de inventario, siempre asociada a
/// un [Lote] específico (nunca a un producto "en general").
///
/// Cuando una venta consume unidades de varios lotes (por ejemplo,
/// agota el lote más antiguo y toma el resto del siguiente), se
/// genera un [Movimiento] de tipo `salida` por cada lote afectado,
/// no uno solo por la venta completa — así cada registro conserva
/// el costo real del lote del que salió.
class Movimiento {
  final int? id;
  final int productoId;
  final int loteId;
  final TipoMovimiento tipo;
  final int cantidad;

  /// Costo unitario de compra si [tipo] es `entrada`, o precio
  /// unitario de venta si [tipo] es `salida`. El mismo campo cambia
  /// de significado según el tipo de movimiento: no representar
  /// ambos casos con nombres separados fue una decisión deliberada
  /// para no duplicar la estructura de la tabla, pero es el campo
  /// con más probabilidad de confundir a quien lea este modelo por
  /// primera vera — al consumirlo, siempre revisar [tipo] primero.
  final double precioUnitario;

  final DateTime fecha;

  Movimiento({
    this.id,
    required this.productoId,
    required this.loteId,
    required this.tipo,
    required this.cantidad,
    required this.precioUnitario,
    required this.fecha,
  });

  /// Convierte la instancia a un mapa compatible con `sqflite`.
  /// [tipo] se guarda como texto plano (`'entrada'` o `'salida'`),
  /// nunca como el índice del enum, para que la base de datos siga
  /// siendo legible directamente y no dependa del orden en que se
  /// declaren los valores de [TipoMovimiento].
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'productoId': productoId,
      'loteId': loteId,
      'tipo': tipo.name, 
      'cantidad': cantidad,
      'precioUnitario': precioUnitario,
      'fecha': fecha.toIso8601String(),
    };
  }

  /// Reconstruye un [Movimiento] a partir de una fila leída de la base de datos.
  factory Movimiento.fromMap(Map<String, dynamic> map) {
    return Movimiento(
      id: map['id'] as int?,
      productoId: map['productoId'] as int,
      loteId: map['loteId'] as int,
      tipo: TipoMovimiento.values.byName(map['tipo'] as String),
      cantidad: map['cantidad'] as int,
      precioUnitario: map['precioUnitario'] as double,
      fecha: DateTime.parse(map['fecha'] as String),
    );
  }
}