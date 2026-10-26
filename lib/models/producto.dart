/// Representa un producto del catálogo del negocio.
///
/// No contiene el stock directamente: la cantidad disponible se
/// calcula sumando sus [Lote] asociados (ver
/// [DatabaseHelper.getStockActual] y [DatabaseHelper.getProductosConStockBatch]),
/// ya que cada lote puede tener un costo y fecha de ingreso distintos.
class Producto {
  final int? id;
  final String nombre;
  final String unidad; // ej: "unidad", "kg", "litro"

  /// Umbral de stock por debajo del cual la app muestra la alerta
  /// visual y dispara la notificación del sistema al registrar una
  /// venta (ver [DatabaseHelper.registrarVentaPEPS] y
  /// `NotificacionService`).
  final int stockMinimo;

  /// Si es `false`, el producto está descontinuado: no genera
  /// alertas de stock bajo y se muestra al final de la lista de
  /// productos, pero conserva todo su historial de lotes y
  /// movimientos intacto. Un producto nunca se elimina de la base
  /// de datos, solo se desactiva (ver
  /// [DatabaseHelper.toggleActivoProducto]).
  final bool activo;

  /// Ruta local del archivo de imagen del producto, dentro del
  /// almacenamiento propio de la app. `null` si el usuario no
  /// asignó ninguna foto.
  final String? imagenPath;

    /// Precio de venta sugerido por unidad, definido manualmente por el
  /// usuario (opcional). Usado por el módulo de oportunidades para
  /// detectar si el producto se está vendiendo por debajo de su
  /// costo real; si es `null`, se usa como respaldo el precio de la
  /// venta más reciente del producto (ver
  /// [DatabaseHelper.getProductosPrecioBajoCosto]).
  final double? precioVentaSugerido;

  Producto({
    this.id,
    required this.nombre,
    required this.unidad,
    required this.stockMinimo,
    this.activo = true,
    this.imagenPath,
    this.precioVentaSugerido,
  });

  /// Convierte la instancia a un mapa compatible con `sqflite`.
  /// [activo] se guarda como `1`/`0`, ya que SQLite no tiene un tipo
  /// booleano nativo.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'unidad': unidad,
      'stockMinimo': stockMinimo,
      'activo': activo ? 1 : 0,
      'imagenPath': imagenPath,
      'precioVentaSugerido': precioVentaSugerido,
    };
  }

  /// Reconstruye un [Producto] a partir de una fila leída de la base
  /// de datos. Si `activo` viene `null` (no debería ocurrir tras la
  /// migración a v2, pero se cubre por seguridad), se asume `true`.
  factory Producto.fromMap(Map<String, dynamic> map) {
    return Producto(
      id: map['id'] as int?,
      nombre: map['nombre'] as String,
      unidad: map['unidad'] as String,
      stockMinimo: map['stockMinimo'] as int,
      activo: (map['activo'] as int? ?? 1) == 1,
      imagenPath: map['imagenPath'] as String?,
      precioVentaSugerido: map['precioVentaSugerido'] as double?
    );
  }

  /// Crea una copia del producto reemplazando únicamente [activo].
  /// Usado para reflejar en memoria el cambio hecho por
  /// [DatabaseHelper.toggleActivoProducto] sin volver a leer el
  /// producto completo de la base de datos.
  Producto copyWith({bool? activo}) {
    return Producto(
      id: id,
      nombre: nombre,
      unidad: unidad,
      stockMinimo: stockMinimo,
      activo: activo ?? this.activo,
      imagenPath: imagenPath,
      precioVentaSugerido: precioVentaSugerido
    );
  }
}