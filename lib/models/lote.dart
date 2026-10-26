/// Representa una entrada de mercancía como unidad independiente.
///
/// En vez de guardar un único número de stock por producto, cada
/// compra se registra como su propio lote, con su propio costo y
/// fecha de ingreso. Esta separación es la que permite implementar
/// el método PEPS (ver [DatabaseHelper.registrarVentaPEPS]): al
/// vender, se consumen primero los lotes con [fechaIngreso] más
/// antigua, y se conserva el costo real de cada uno en vez de
/// promediarlos entre sí.
class Lote {
  final int? id;
  final int productoId;

  /// Cantidad que queda disponible en este lote, no la cantidad
  /// original de la compra. Se va descontando con cada venta que
  /// consume unidades de este lote, hasta llegar a 0.
  final int cantidad;

  final double costoUnitario;
  final DateTime fechaIngreso;

  Lote({
    this.id,
    required this.productoId,
    required this.cantidad,
    required this.costoUnitario,
    required this.fechaIngreso,
  });

  /// Convierte la instancia a un mapa compatible con `sqflite`.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'productoId': productoId,
      'cantidad': cantidad,
      'costoUnitario': costoUnitario,
      'fechaIngreso': fechaIngreso.toIso8601String(),
    };
  }

  /// Reconstruye un [Lote] a partir de una fila leída de la base de datos.
  factory Lote.fromMap(Map<String, dynamic> map) {
    return Lote(
      id: map['id'] as int?,
      productoId: map['productoId'] as int,
      cantidad: map['cantidad'] as int,
      costoUnitario: map['costoUnitario'] as double,
      fechaIngreso: DateTime.parse(map['fechaIngreso'] as String),
    );
  }
}