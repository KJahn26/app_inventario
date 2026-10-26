import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/lote.dart';
import '../models/movimiento.dart';
import '../models/producto.dart';

/// Acceso centralizado a la base de datos SQLite local de la app.
///
/// Implementado como singleton ([instance]) para garantizar que toda
/// la app comparta una única conexión abierta a la base de datos.
/// No existe backend remoto: toda la persistencia vive en el archivo
/// `inventario.db` dentro del almacenamiento privado del dispositivo.
///
/// Modelo de datos:
/// - `producto`: catálogo de productos (activos o descontinuados).
/// - `lote`: cada compra de un producto, con su costo y su cantidad
///   restante. El stock de un producto es la suma de sus lotes.
/// - `movimiento`: historial de todo lo que ocurre con el stock
///   (`entrada`, `salida`, `perdida`, `ganancia`), siempre ligado al
///   lote afectado para conservar el costo real.
/// - `conteo_fisico`: conteos manuales contra el stock del sistema.
///
/// El archivo está organizado en secciones, en este orden:
/// 1. Conexión y esquema
/// 2. Productos
/// 3. Lotes y stock
/// 4. Movimientos (consulta)
/// 5. Operaciones de inventario (entradas y ventas PEPS)
/// 6. Conteo físico y diferencias de inventario
/// 7. Resumen financiero y ventas por periodo
/// 8. Módulo de oportunidades
/// 9. Informe ejecutivo por rango de fechas
/// 10. Mantenimiento (reseteo de la base de datos)
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  DatabaseHelper._internal();

  static const String _nombreArchivo = 'inventario.db';

  /// Versión actual del esquema. Cada vez que se cambie la estructura
  /// de las tablas hay que subirla y agregar su bloque en [_onUpgrade].
  static const int _versionEsquema = 7;

  static Database? _database;

  // ===========================================================
  // 1. CONEXIÓN Y ESQUEMA
  // ===========================================================

  /// Devuelve la conexión activa a la base de datos, abriéndola
  /// (y ejecutando migraciones si aplica) la primera vez que se usa.
  Future<Database> get database async {
    return _database ??= await _initDatabase();
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), _nombreArchivo);
    return await openDatabase(
      path,
      version: _versionEsquema,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Crea el esquema desde cero para instalaciones nuevas (sin historial
  /// previo que migrar). Debe mantenerse en sincronía con el resultado
  /// final de [_onUpgrade]: cualquier columna, tabla o índice agregado
  /// allá debe existir también aquí.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE producto (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        unidad TEXT NOT NULL,
        stockMinimo INTEGER NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        imagenPath TEXT,
        precioVentaSugerido REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE lote (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        productoId INTEGER NOT NULL,
        cantidad INTEGER NOT NULL,
        costoUnitario REAL NOT NULL,
        fechaIngreso TEXT NOT NULL,
        FOREIGN KEY (productoId) REFERENCES producto (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE movimiento (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        productoId INTEGER NOT NULL,
        loteId INTEGER NOT NULL,
        tipo TEXT NOT NULL,
        cantidad INTEGER NOT NULL,
        precioUnitario REAL NOT NULL,
        fecha TEXT NOT NULL,
        FOREIGN KEY (productoId) REFERENCES producto (id),
        FOREIGN KEY (loteId) REFERENCES lote (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE conteo_fisico (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        productoId INTEGER NOT NULL,
        cantidadSistema INTEGER NOT NULL,
        cantidadContada INTEGER NOT NULL,
        diferencia INTEGER NOT NULL,
        resuelto INTEGER NOT NULL DEFAULT 0,
        fecha TEXT NOT NULL,
        FOREIGN KEY (productoId) REFERENCES producto (id)
      )
    ''');

    await _crearIndices(db);
  }

  /// Índices que evitan que las consultas se degraden a medida que
  /// crece el catálogo o el historial. Se usan tanto en [_onCreate]
  /// como en la migración a la versión 4 y 6 (`IF NOT EXISTS` permite
  /// llamarlo en ambos casos sin riesgo).
  Future<void> _crearIndices(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_lote_producto ON lote(productoId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_movimiento_producto ON movimiento(productoId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_movimiento_fecha ON movimiento(fecha)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_conteo_producto ON conteo_fisico(productoId)');
  }

  /// Aplica las migraciones necesarias cuando un usuario actualiza la app
  /// y su base de datos local quedó en una versión anterior.
  ///
  /// Cada bloque `if (oldVersion < N)` es acumulativo: si alguien viene
  /// desde la versión 1, se ejecutan en orden todos los cambios hasta
  /// la versión actual. Nunca se borran datos existentes, solo se
  /// agregan columnas, tablas e índices.
  ///
  /// Historial de versiones:
  /// - v2: agrega `producto.activo` (permite descontinuar sin eliminar).
  /// - v3: agrega `producto.imagenPath` (foto del producto).
  /// - v4: agrega índices sobre `lote.productoId`, `movimiento.productoId`
  ///   y `movimiento.fecha`.
  /// - v5: agrega `producto.precioVentaSugerido`.
  /// - v6: agrega la tabla `conteo_fisico` y su índice.
  /// - v7: agrega `conteo_fisico.resuelto` (marca los conteos ya
  ///   atendidos). Se comprueba si la columna ya existe porque quien
  ///   migra desde una versión anterior a la 6 recibe la tabla ya
  ///   creada con esa columna.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE producto ADD COLUMN activo INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE producto ADD COLUMN imagenPath TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_lote_producto ON lote(productoId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_movimiento_producto ON movimiento(productoId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_movimiento_fecha ON movimiento(fecha)');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE producto ADD COLUMN precioVentaSugerido REAL');
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS conteo_fisico (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          productoId INTEGER NOT NULL,
          cantidadSistema INTEGER NOT NULL,
          cantidadContada INTEGER NOT NULL,
          diferencia INTEGER NOT NULL,
          resuelto INTEGER NOT NULL DEFAULT 0,
          fecha TEXT NOT NULL,
          FOREIGN KEY (productoId) REFERENCES producto (id)
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_conteo_producto ON conteo_fisico(productoId)');
    }
    if (oldVersion < 7) {
      if (!await _columnaExiste(db, 'conteo_fisico', 'resuelto')) {
        await db.execute(
          'ALTER TABLE conteo_fisico ADD COLUMN resuelto INTEGER NOT NULL DEFAULT 0',
        );
      }
    }
  }

  /// Indica si [tabla] ya tiene una columna llamada [columna].
  /// Permite que las migraciones sean idempotentes.
  Future<bool> _columnaExiste(DatabaseExecutor db, String tabla, String columna) async {
    final columnas = await db.rawQuery('PRAGMA table_info($tabla)');
    return columnas.any((c) => c['name'] == columna);
  }

  // ===========================================================
  // 2. PRODUCTOS
  // ===========================================================

  /// Inserta un producto nuevo y devuelve su id.
  Future<int> insertProducto(Producto producto) async {
    final db = await database;
    return await db.insert('producto', producto.toMap());
  }

  /// Actualiza todos los campos editables de un producto existente.
  ///
  /// A diferencia de [toggleActivoProducto] y [actualizarPrecioSugerido]
  /// (que tocan un solo campo puntual), este reemplaza nombre, unidad,
  /// stock mínimo, imagen y precio sugerido de una sola vez; lo usa la
  /// pantalla de edición completa del producto.
  Future<void> actualizarProducto(Producto producto) async {
    final db = await database;
    final datos = producto.toMap()..remove('id');
    await db.update('producto', datos, where: 'id = ?', whereArgs: [producto.id]);
  }

  /// Cambia únicamente el precio de venta sugerido de un producto.
  /// Pasar `null` lo elimina.
  Future<void> actualizarPrecioSugerido(int productoId, double? precio) async {
    final db = await database;
    await db.update(
      'producto',
      {'precioVentaSugerido': precio},
      where: 'id = ?',
      whereArgs: [productoId],
    );
  }

  /// Marca un producto como activo o descontinuado.
  ///
  /// No elimina el producto ni su historial: un producto descontinuado
  /// conserva todos sus [Lote] y [Movimiento] para efectos de reportes,
  /// pero deja de generar alertas y se muestra al final de la lista de
  /// productos (ver [getProductos]).
  Future<void> toggleActivoProducto(int id, bool activo) async {
    final db = await database;
    await db.update(
      'producto',
      {'activo': activo ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Devuelve el producto con ese [id], o `null` si no existe.
  Future<Producto?> getProducto(int id) async {
    final db = await database;
    final maps = await db.query('producto', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Producto.fromMap(maps.first);
  }

  /// Productos ordenados con los activos primero (y por nombre dentro
  /// de cada grupo). No incluye el stock actual de cada uno; para eso
  /// usar [getProductosConStockBatch], que es más eficiente.
  Future<List<Producto>> getProductos() async {
    final db = await database;
    final maps = await db.query(
      'producto',
      orderBy: 'activo DESC, nombre ASC',
    );
    return maps.map((m) => Producto.fromMap(m)).toList();
  }

  /// Todos los productos junto con su stock actual (suma de sus lotes,
  /// columna `stockActual`), calculado en una sola consulta SQL
  /// (`LEFT JOIN` + `GROUP BY`).
  ///
  /// Evita el patrón de pedir [getProductos] y luego llamar
  /// [getStockActual] en un bucle por cada uno (consultas N+1), que
  /// escala mal con catálogos grandes. Usar este método para cualquier
  /// pantalla que liste productos con su stock, como la lista
  /// principal o la exportación a Excel.
  Future<List<Map<String, dynamic>>> getProductosConStockBatch() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT p.*, COALESCE(SUM(l.cantidad), 0) AS stockActual
      FROM producto p
      LEFT JOIN lote l ON l.productoId = p.id
      GROUP BY p.id
      ORDER BY p.activo DESC, p.nombre ASC
    ''');
  }

  // ===========================================================
  // 3. LOTES Y STOCK
  // ===========================================================

  /// Inserta un lote nuevo y devuelve su id. Para registrar una compra
  /// completa (lote + movimiento) usar [registrarEntrada].
  Future<int> insertLote(Lote lote) async {
    final db = await database;
    return await db.insert('lote', lote.toMap());
  }

  /// Fija la cantidad restante de un lote.
  Future<void> actualizarCantidadLote(int loteId, int nuevaCantidad) async {
    final db = await database;
    await db.update(
      'lote',
      {'cantidad': nuevaCantidad},
      where: 'id = ?',
      whereArgs: [loteId],
    );
  }

  /// Lotes con unidades disponibles (`cantidad > 0`) de un producto,
  /// ordenados del más antiguo al más reciente por `fechaIngreso`.
  ///
  /// Este orden es el corazón del método PEPS: las operaciones que
  /// consumen stock recorren esta lista en el orden en que la devuelve
  /// la consulta, sin reordenar nada en Dart.
  Future<List<Lote>> getLotesDisponiblesPEPS(int productoId) async {
    final db = await database;
    return _lotesDisponiblesEn(db, productoId);
  }

  /// Stock total actual de un producto (suma de sus lotes). Devuelve 0
  /// si el producto no tiene lotes.
  Future<int> getStockActual(int productoId) async {
    final db = await database;
    return _stockActualEn(db, productoId);
  }

  /// Versión de [getLotesDisponiblesPEPS] que acepta un
  /// [DatabaseExecutor], para poder usarla dentro de una transacción.
  Future<List<Lote>> _lotesDisponiblesEn(DatabaseExecutor ex, int productoId) async {
    final maps = await ex.query(
      'lote',
      where: 'productoId = ? AND cantidad > 0',
      whereArgs: [productoId],
      orderBy: 'fechaIngreso ASC',
    );
    return maps.map((m) => Lote.fromMap(m)).toList();
  }

  /// Versión de [getStockActual] que acepta un [DatabaseExecutor],
  /// para poder usarla dentro de una transacción.
  Future<int> _stockActualEn(DatabaseExecutor ex, int productoId) async {
    final result = await ex.rawQuery(
      'SELECT COALESCE(SUM(cantidad), 0) AS total FROM lote WHERE productoId = ?',
      [productoId],
    );
    return (result.first['total'] as num).toInt();
  }

  // ===========================================================
  // 4. MOVIMIENTOS (CONSULTA)
  // ===========================================================

  /// Inserta un movimiento suelto y devuelve su id. Para registrar
  /// entradas y ventas completas usar [registrarEntrada] y
  /// [registrarVentaPEPS], que mantienen lotes y movimientos coherentes.
  Future<int> insertMovimiento(Movimiento movimiento) async {
    final db = await database;
    return await db.insert('movimiento', movimiento.toMap());
  }

  /// Todos los movimientos como objetos [Movimiento], del más reciente
  /// al más antiguo. No incluye nombre de producto ni datos del lote;
  /// para eso usar [getMovimientosConNombreProducto].
  Future<List<Movimiento>> getMovimientos() async {
    final db = await database;
    final maps = await db.query('movimiento', orderBy: 'fecha DESC');
    return maps.map((m) => Movimiento.fromMap(m)).toList();
  }

  /// Historial completo de movimientos, del más antiguo al más reciente,
  /// con el nombre del producto (`nombreProducto`, `unidadProducto`) y
  /// el detalle del lote de origen (`costoLote`, `fechaLote`).
  ///
  /// El join con lote es lo que permite mostrar la trazabilidad
  /// completa detrás de cada cifra: de qué compra salió, a qué costo,
  /// y qué ganancia o pérdida generó ese movimiento en particular.
  Future<List<Map<String, dynamic>>> getMovimientosConNombreProducto() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT m.*, p.nombre AS nombreProducto, p.unidad AS unidadProducto,
             l.costoUnitario AS costoLote, l.fechaIngreso AS fechaLote
      FROM movimiento m
      JOIN producto p ON m.productoId = p.id
      JOIN lote l ON m.loteId = l.id
      ORDER BY m.fecha ASC
    ''');
  }

  /// Página de movimientos, más nuevos primero, con el mismo detalle
  /// que [getMovimientosConNombreProducto]. Pensada para listas largas:
  /// evita cargar todo el historial de una sola vez.
  Future<List<Map<String, dynamic>>> getMovimientosPaginados({
    required int limite,
    required int offset,
  }) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT m.*, p.nombre AS nombreProducto, p.unidad AS unidadProducto,
             l.costoUnitario AS costoLote, l.fechaIngreso AS fechaLote
      FROM movimiento m
      JOIN producto p ON m.productoId = p.id
      JOIN lote l ON m.loteId = l.id
      ORDER BY m.fecha DESC
      LIMIT ? OFFSET ?
    ''', [limite, offset]);
  }

  // ===========================================================
  // 5. OPERACIONES DE INVENTARIO (ENTRADAS Y VENTAS PEPS)
  // ===========================================================

  /// Registra una entrada de stock: crea un [Lote] nuevo con su costo
  /// y fecha de ingreso, y su [Movimiento] espejo de tipo `entrada`.
  ///
  /// Cada llamada crea un lote independiente aunque ya existan otros
  /// del mismo producto (nunca se suma al lote existente), porque el
  /// costo de cada compra puede variar y PEPS necesita distinguirlos.
  ///
  /// Ambas escrituras ocurren en una transacción: o se guardan las dos
  /// o no se guarda ninguna.
  Future<void> registrarEntrada({
    required int productoId,
    required int cantidad,
    required double costoUnitario,
  }) async {
    final db = await database;
    final ahora = DateTime.now();

    await db.transaction((txn) async {
      final loteId = await txn.insert(
        'lote',
        Lote(
          productoId: productoId,
          cantidad: cantidad,
          costoUnitario: costoUnitario,
          fechaIngreso: ahora,
        ).toMap(),
      );

      await txn.insert(
        'movimiento',
        Movimiento(
          productoId: productoId,
          loteId: loteId,
          tipo: TipoMovimiento.entrada,
          cantidad: cantidad,
          precioUnitario: costoUnitario,
          fecha: ahora,
        ).toMap(),
      );
    });
  }

  /// Registra una venta descontando stock mediante el método PEPS
  /// (Primeras Entradas, Primeras Salidas).
  ///
  /// Pasos:
  /// 1. Verifica que el stock total del producto alcance para la
  ///    cantidad vendida; si no, no modifica nada.
  /// 2. Descuenta la cantidad empezando por el lote más antiguo,
  ///    pasando al siguiente si este se agota (ver [_consumirLotesPEPS]).
  /// 3. Por cada lote afectado inserta un [Movimiento] de tipo `salida`
  ///    independiente, conservando el costo real de ESE lote: así una
  ///    venta que cruza dos lotes con costos distintos no promedia el
  ///    costo, lo mantiene exacto por lote.
  ///
  /// Todo ocurre en una transacción, de modo que una venta nunca queda
  /// a medias. Devuelve `false` sin modificar nada si el stock es
  /// insuficiente.
  Future<bool> registrarVentaPEPS({
    required int productoId,
    required int cantidadVendida,
    required double precioVenta,
  }) async {
    final db = await database;

    return await db.transaction<bool>((txn) async {
      final stockActual = await _stockActualEn(txn, productoId);
      if (stockActual < cantidadVendida) return false;

      await _consumirLotesPEPS(
        txn,
        productoId: productoId,
        cantidad: cantidadVendida,
        tipo: TipoMovimiento.salida,
        precioUnitario: precioVenta,
      );
      return true;
    });
  }

  /// Descuenta [cantidad] unidades de los lotes de un producto, del más
  /// antiguo al más reciente, y registra un [Movimiento] del [tipo]
  /// indicado por cada lote tocado.
  ///
  /// Lo comparten las ventas ([registrarVentaPEPS]) y las pérdidas por
  /// faltante ([registrarIncidenteInventario]), que descuentan stock de
  /// la misma forma y solo difieren en el tipo y el precio del
  /// movimiento. No verifica que haya stock suficiente: eso es
  /// responsabilidad de quien lo llama.
  Future<void> _consumirLotesPEPS(
    DatabaseExecutor ex, {
    required int productoId,
    required int cantidad,
    required TipoMovimiento tipo,
    required double precioUnitario,
  }) async {
    final lotes = await _lotesDisponiblesEn(ex, productoId);
    final ahora = DateTime.now();
    int restante = cantidad;

    for (final lote in lotes) {
      if (restante <= 0) break;

      final cantidadATomar = lote.cantidad <= restante ? lote.cantidad : restante;

      await ex.update(
        'lote',
        {'cantidad': lote.cantidad - cantidadATomar},
        where: 'id = ?',
        whereArgs: [lote.id],
      );

      await ex.insert(
        'movimiento',
        Movimiento(
          productoId: productoId,
          loteId: lote.id!,
          tipo: tipo,
          cantidad: cantidadATomar,
          precioUnitario: precioUnitario,
          fecha: ahora,
        ).toMap(),
      );

      restante -= cantidadATomar;
    }
  }

  // ===========================================================
  // 6. CONTEO FÍSICO Y DIFERENCIAS DE INVENTARIO
  // ===========================================================

  /// Registra un conteo físico: compara [cantidadContada] contra el
  /// stock que el sistema tiene calculado, guarda la diferencia y
  /// devuelve el id del conteo creado.
  ///
  /// No ajusta el stock por sí solo: queda marcado como pendiente
  /// (`resuelto = 0`) hasta que el usuario decida qué hacer vía
  /// [registrarIncidenteInventario].
  Future<int> registrarConteoFisico({
    required int productoId,
    required int cantidadContada,
  }) async {
    final db = await database;
    final cantidadSistema = await _stockActualEn(db, productoId);
    final diferencia = cantidadContada - cantidadSistema;

    return await db.insert('conteo_fisico', {
      'productoId': productoId,
      'cantidadSistema': cantidadSistema,
      'cantidadContada': cantidadContada,
      'diferencia': diferencia,
      'resuelto': 0,
      'fecha': DateTime.now().toIso8601String(),
    });
  }

  /// Conteos físicos pendientes de revisión: el más reciente por
  /// producto, con diferencia distinta de cero y aún no resuelto.
  /// Cada fila trae los datos del conteo más `nombre` y `unidad` del
  /// producto, ordenados por la magnitud de la diferencia.
  Future<List<Map<String, dynamic>>> getUltimasDiferenciasInventario() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT c.*, p.nombre, p.unidad
      FROM conteo_fisico c
      JOIN producto p ON p.id = c.productoId
      WHERE c.resuelto = 0
        AND c.diferencia != 0
        AND c.fecha = (
          SELECT MAX(c2.fecha) FROM conteo_fisico c2
          WHERE c2.productoId = c.productoId AND c2.resuelto = 0
        )
      ORDER BY ABS(c.diferencia) DESC
    ''');
  }

  /// Aplica la decisión del usuario sobre una diferencia de inventario
  /// detectada en [conteoId], registrando el incidente como un
  /// movimiento real en el historial:
  /// - Faltante (diferencia negativa): descuenta stock vía PEPS, igual
  ///   que una venta pero sin precio de venta (tipo `perdida`),
  ///   reflejando el costo perdido de esas unidades.
  /// - Sobrante (diferencia positiva): crea un lote nuevo con esa
  ///   cantidad, valorado al costo del lote más reciente del producto
  ///   (o 0 si el producto no tenía lotes), tipo `ganancia`.
  ///
  /// Marca el conteo como `resuelto` al terminar, para que no se vuelva
  /// a mostrar como pendiente. Si el conteo no existe o ya estaba
  /// resuelto no hace nada, de modo que no se puede aplicar dos veces.
  /// Todo ocurre en una transacción.
  Future<void> registrarIncidenteInventario(int conteoId) async {
    final db = await database;

    await db.transaction((txn) async {
      final conteoRows = await txn.query(
        'conteo_fisico',
        where: 'id = ?',
        whereArgs: [conteoId],
      );
      if (conteoRows.isEmpty) return;

      final conteo = conteoRows.first;
      if ((conteo['resuelto'] as int) == 1) return;

      final productoId = conteo['productoId'] as int;
      final diferencia = conteo['diferencia'] as int;

      if (diferencia < 0) {
        // Faltante: se consume de los lotes como una venta, sin ingreso.
        await _consumirLotesPEPS(
          txn,
          productoId: productoId,
          cantidad: -diferencia,
          tipo: TipoMovimiento.perdida,
          precioUnitario: 0, // no genera ingreso: es una pérdida de costo
        );
      } else if (diferencia > 0) {
        // Sobrante: se crea un lote nuevo, valorado al costo más reciente conocido.
        final ultimoLote = await txn.query(
          'lote',
          where: 'productoId = ?',
          whereArgs: [productoId],
          orderBy: 'fechaIngreso DESC',
          limit: 1,
        );
        final costoReferencia = ultimoLote.isNotEmpty
            ? (ultimoLote.first['costoUnitario'] as num).toDouble()
            : 0.0;
        final ahora = DateTime.now();

        final loteId = await txn.insert(
          'lote',
          Lote(
            productoId: productoId,
            cantidad: diferencia,
            costoUnitario: costoReferencia,
            fechaIngreso: ahora,
          ).toMap(),
        );

        await txn.insert(
          'movimiento',
          Movimiento(
            productoId: productoId,
            loteId: loteId,
            tipo: TipoMovimiento.ganancia,
            cantidad: diferencia,
            precioUnitario: costoReferencia,
            fecha: ahora,
          ).toMap(),
        );
      }

      await txn.update(
        'conteo_fisico',
        {'resuelto': 1},
        where: 'id = ?',
        whereArgs: [conteoId],
      );
    });
  }

  // ===========================================================
  // 7. RESUMEN FINANCIERO Y VENTAS POR PERIODO
  // ===========================================================

  /// Resumen financiero acumulado de todo el historial.
  ///
  /// La ganancia NO se calcula como "ventas − compras", sino como
  /// `ventas − costoVendido − costoPerdidas + valorGananciasSobrantes`.
  /// El costo de lo vendido se obtiene uniendo cada [Movimiento] de
  /// salida con el [Lote] del que salió, usando el costo real de ese
  /// lote específico (coherente con la lógica PEPS). Esto evita
  /// distorsionar la ganancia cuando hay stock comprado a distinto
  /// costo todavía sin vender.
  ///
  /// Devuelve un mapa con las claves: `totalGastado`, `totalVentas`,
  /// `costoVendido`, `costoPerdidas`, `valorGananciasSobrantes` y
  /// `ganancia`.
  Future<Map<String, double>> getResumenFinanciero() async {
    final db = await database;
    return _calcularResumenFinanciero(db);
  }

  /// Igual que [getResumenFinanciero], pero acotado a un único periodo
  /// (ej. solo septiembre de 2026, o solo el tercer trimestre de 2026),
  /// identificado por [valorPeriodo] tal como lo devuelve
  /// [getPeriodosDisponibles]. [periodo] puede ser `'mensual'`,
  /// `'trimestral'` o `'anual'`. Incluye también el costo de pérdidas
  /// por faltantes y el valor de ganancias por sobrantes detectados en
  /// conteos físicos dentro de ese mismo periodo.
  Future<Map<String, double>> getResumenFinancieroPorPeriodo(
    String periodo,
    String valorPeriodo,
  ) async {
    final db = await database;
    return _calcularResumenFinanciero(
      db,
      filtroFecha: "${_agrupadorPeriodo(periodo, 'm.fecha')} = ?",
      argumento: valorPeriodo,
    );
  }

  /// Calcula el resumen financiero sobre todo el historial o, si se da
  /// [filtroFecha] (una condición SQL sobre `m.fecha` con un `?`) y su
  /// [argumento], solo sobre los movimientos que la cumplan. Es la
  /// única implementación del cálculo: el resumen total y el de
  /// periodo no pueden divergir.
  Future<Map<String, double>> _calcularResumenFinanciero(
    DatabaseExecutor db, {
    String? filtroFecha,
    String? argumento,
  }) async {
    final condicion = filtroFecha == null ? '' : 'AND $filtroFecha';
    final args = argumento == null ? <Object?>[] : <Object?>[argumento];

    Future<double> suma(String sql) async {
      final r = await db.rawQuery(sql, args);
      return (r.first['total'] as num?)?.toDouble() ?? 0.0;
    }

    // Total gastado en reposición (todas las entradas).
    final totalGastado = await suma('''
      SELECT SUM(m.cantidad * m.precioUnitario) AS total
      FROM movimiento m
      WHERE m.tipo = 'entrada' $condicion
    ''');

    // Total de ingresos por ventas.
    final totalVentas = await suma('''
      SELECT SUM(m.cantidad * m.precioUnitario) AS total
      FROM movimiento m
      WHERE m.tipo = 'salida' $condicion
    ''');

    // Costo real de lo vendido (usando el costo del lote de cada salida).
    final costoVendido = await suma('''
      SELECT SUM(m.cantidad * l.costoUnitario) AS total
      FROM movimiento m
      JOIN lote l ON m.loteId = l.id
      WHERE m.tipo = 'salida' $condicion
    ''');

    // Costo de las pérdidas por faltantes (conteo físico).
    final costoPerdidas = await suma('''
      SELECT SUM(m.cantidad * l.costoUnitario) AS total
      FROM movimiento m
      JOIN lote l ON m.loteId = l.id
      WHERE m.tipo = 'perdida' $condicion
    ''');

    // Valor de las ganancias por sobrantes (conteo físico).
    final valorGananciasSobrantes = await suma('''
      SELECT SUM(m.cantidad * m.precioUnitario) AS total
      FROM movimiento m
      WHERE m.tipo = 'ganancia' $condicion
    ''');

    return {
      'totalGastado': totalGastado,
      'totalVentas': totalVentas,
      'costoVendido': costoVendido,
      'costoPerdidas': costoPerdidas,
      'valorGananciasSobrantes': valorGananciasSobrantes,
      'ganancia': totalVentas - costoVendido - costoPerdidas + valorGananciasSobrantes,
    };
  }

  /// Valores de periodo distintos que existen en el historial de
  /// movimientos (ej. `'2026-09'`, `'2026-T3'`, `'2026'`), del más
  /// reciente al más antiguo. Pensado para poblar el dropdown de
  /// selección de periodo en el resumen financiero.
  Future<List<String>> getPeriodosDisponibles(String periodo) async {
    final db = await database;
    final agrupador = _agrupadorPeriodo(periodo, 'fecha');

    final result = await db.rawQuery('''
      SELECT DISTINCT $agrupador AS periodo
      FROM movimiento
      ORDER BY periodo DESC
    ''');

    return result.map((r) => r['periodo'] as String).toList();
  }

  /// Unidades vendidas por producto, agrupadas por periodo
  /// (`'mensual'`, `'trimestral'` o `'anual'`), para alimentar la
  /// gráfica de líneas de la pantalla de ventas.
  ///
  /// Devuelve un mapa `nombreProducto -> lista de filas`, donde cada
  /// fila trae `periodo` y `totalVendido`. Se agrupa por producto en
  /// Dart (no en SQL) porque cada producto necesita su propia serie de
  /// puntos para dibujarse como una línea independiente en el gráfico.
  Future<Map<String, List<Map<String, dynamic>>>> getVentasPorPeriodoPorProducto(
    String periodo,
  ) async {
    final db = await database;
    final agrupador = _agrupadorPeriodo(periodo, 'm.fecha');

    final result = await db.rawQuery('''
      SELECT p.id AS productoId, p.nombre AS nombreProducto,
             $agrupador AS periodo, SUM(m.cantidad) AS totalVendido
      FROM movimiento m
      JOIN producto p ON m.productoId = p.id
      WHERE m.tipo = 'salida'
      GROUP BY p.id, periodo
      ORDER BY p.id, periodo ASC
    ''');

    final Map<String, List<Map<String, dynamic>>> porProducto = {};
    for (final fila in result) {
      final nombre = fila['nombreProducto'] as String;
      porProducto.putIfAbsent(nombre, () => []).add(fila);
    }

    return porProducto;
  }

  /// Arma el fragmento SQL que agrupa una columna de fecha por
  /// `'mensual'` (`'YYYY-MM'`), `'trimestral'` (`'YYYY-TN'`) o
  /// `'anual'` (`'YYYY'`); cualquier otro valor se trata como mensual.
  ///
  /// Centralizado aquí para que el resumen financiero y las gráficas
  /// de ventas agrupen siempre de la misma forma, sin duplicar la
  /// lógica del cálculo de trimestre.
  String _agrupadorPeriodo(String periodo, String campoFecha) {
    switch (periodo) {
      case 'trimestral':
        return "strftime('%Y', $campoFecha) || '-T' || ((CAST(strftime('%m', $campoFecha) AS INTEGER) - 1) / 3 + 1)";
      case 'anual':
        return "strftime('%Y', $campoFecha)";
      case 'mensual':
      default:
        return "strftime('%Y-%m', $campoFecha)";
    }
  }

  // ===========================================================
  // 8. MÓDULO DE OPORTUNIDADES
  // ===========================================================

  /// Productos activos con stock disponible cuyo precio de referencia
  /// es menor al costo real del lote más antiguo disponible (el
  /// próximo que PEPS va a consumir).
  ///
  /// El precio de referencia es [Producto.precioVentaSugerido] o, si no
  /// existe, el precio de su venta más reciente.
  ///
  /// Cada fila trae: `id`, `nombre`, `unidad`, `precioReferencia` y
  /// `costoReferencia`. Solo se devuelven los productos con
  /// `precioReferencia < costoReferencia` (se venden perdiendo dinero).
  Future<List<Map<String, dynamic>>> getProductosPrecioBajoCosto() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT
        p.id, p.nombre, p.unidad,
        COALESCE(
          p.precioVentaSugerido,
          (SELECT m.precioUnitario FROM movimiento m
            WHERE m.productoId = p.id AND m.tipo = 'salida'
            ORDER BY m.fecha DESC LIMIT 1)
        ) AS precioReferencia,
        (SELECT l.costoUnitario FROM lote l
          WHERE l.productoId = p.id AND l.cantidad > 0
          ORDER BY l.fechaIngreso ASC LIMIT 1) AS costoReferencia
      FROM producto p
      WHERE p.activo = 1
        AND (SELECT COALESCE(SUM(cantidad), 0) FROM lote WHERE productoId = p.id) > 0
    ''');

    // El filtro de "precio < costo" se aplica en Dart porque ambos
    // valores vienen de subconsultas que SQLite no puede comparar
    // directamente dentro del WHERE sin repetirlas.
    return result.where((fila) {
      final precio = fila['precioReferencia'] as num?;
      final costo = fila['costoReferencia'] as num?;
      return precio != null && costo != null && precio < costo;
    }).toList();
  }

  /// Productos activos sin ningún movimiento de salida en los últimos
  /// [dias] días (por defecto 30). Incluye productos que nunca se han
  /// vendido. Cada fila trae `id`, `nombre`, `unidad` y la fecha de la
  /// última venta (`ultimaVenta`, puede ser `null`).
  Future<List<Map<String, dynamic>>> getProductosSinVentasRecientes({int dias = 30}) async {
    final db = await database;
    final limite = DateTime.now().subtract(Duration(days: dias)).toIso8601String();

    return await db.rawQuery('''
      SELECT p.id, p.nombre, p.unidad,
        (SELECT MAX(m.fecha) FROM movimiento m
          WHERE m.productoId = p.id AND m.tipo = 'salida') AS ultimaVenta
      FROM producto p
      WHERE p.activo = 1
        AND NOT EXISTS (
          SELECT 1 FROM movimiento m
          WHERE m.productoId = p.id AND m.tipo = 'salida' AND m.fecha >= ?
        )
      ORDER BY ultimaVenta ASC
    ''', [limite]);
  }

  /// Productos activos con stock disponible que no registraron ninguna
  /// venta en los últimos [dias] días (por defecto 90), con el valor
  /// monetario inmovilizado (`valorInmovilizado` = cantidad de cada
  /// lote × su costo real, sumado) y `stockActual`. Ordenados del
  /// mayor al menor valor inmovilizado.
  Future<List<Map<String, dynamic>>> getMercanciaBajaRotacion({int dias = 90}) async {
    final db = await database;
    final limite = DateTime.now().subtract(Duration(days: dias)).toIso8601String();

    return await db.rawQuery('''
      SELECT p.id, p.nombre, p.unidad,
        (SELECT COALESCE(SUM(l.cantidad), 0) FROM lote l WHERE l.productoId = p.id) AS stockActual,
        (SELECT COALESCE(SUM(l.cantidad * l.costoUnitario), 0) FROM lote l WHERE l.productoId = p.id) AS valorInmovilizado
      FROM producto p
      WHERE p.activo = 1
        AND (SELECT COALESCE(SUM(cantidad), 0) FROM lote WHERE productoId = p.id) > 0
        AND NOT EXISTS (
          SELECT 1 FROM movimiento m
          WHERE m.productoId = p.id AND m.tipo = 'salida' AND m.fecha >= ?
        )
      ORDER BY valorInmovilizado DESC
    ''', [limite]);
  }

  // ===========================================================
  // 9. INFORME EJECUTIVO (RANGO DE FECHAS)
  // ===========================================================

  /// Resumen financiero acotado a [inicio]..[fin] (inclusive) para el
  /// informe PDF: ventas, costo de lo vendido, gasto en compras, y el
  /// número de ventas (movimientos de salida) y total de unidades
  /// vendidas en el periodo.
  ///
  /// Claves del mapa: `totalVentas`, `costoVendido`, `gananciaBruta`,
  /// `totalGastado`, `unidadesVendidas` y `numVentas`. A diferencia de
  /// [getResumenFinanciero], la `gananciaBruta` es solo
  /// `ventas − costoVendido`: no descuenta pérdidas ni suma sobrantes
  /// de conteos físicos.
  Future<Map<String, dynamic>> getResumenFinancieroPorRango(DateTime inicio, DateTime fin) async {
    final db = await database;
    final inicioStr = inicio.toIso8601String();
    final finStr = fin.toIso8601String();

    final ventasResult = await db.rawQuery('''
      SELECT SUM(cantidad * precioUnitario) AS total, SUM(cantidad) AS unidades, COUNT(*) AS numVentas
      FROM movimiento
      WHERE tipo = 'salida' AND fecha BETWEEN ? AND ?
    ''', [inicioStr, finStr]);
    final totalVentas = (ventasResult.first['total'] as num?)?.toDouble() ?? 0.0;
    final unidadesVendidas = (ventasResult.first['unidades'] as num?)?.toInt() ?? 0;
    final numVentas = (ventasResult.first['numVentas'] as num?)?.toInt() ?? 0;

    final costoVendidoResult = await db.rawQuery('''
      SELECT SUM(m.cantidad * l.costoUnitario) AS total
      FROM movimiento m
      JOIN lote l ON m.loteId = l.id
      WHERE m.tipo = 'salida' AND m.fecha BETWEEN ? AND ?
    ''', [inicioStr, finStr]);
    final costoVendido = (costoVendidoResult.first['total'] as num?)?.toDouble() ?? 0.0;

    final entradasResult = await db.rawQuery('''
      SELECT SUM(cantidad * precioUnitario) AS total
      FROM movimiento
      WHERE tipo = 'entrada' AND fecha BETWEEN ? AND ?
    ''', [inicioStr, finStr]);
    final totalGastado = (entradasResult.first['total'] as num?)?.toDouble() ?? 0.0;

    return {
      'totalVentas': totalVentas,
      'costoVendido': costoVendido,
      'gananciaBruta': totalVentas - costoVendido,
      'totalGastado': totalGastado,
      'unidadesVendidas': unidadesVendidas,
      'numVentas': numVentas,
    };
  }

  /// Unidades (`unidades`) y valor vendido (`valor`) por día (`dia`,
  /// formato `YYYY-MM-DD`) dentro de [inicio]..[fin], ordenado
  /// cronológicamente. Alimenta el gráfico de evolución diaria y
  /// permite identificar el mejor día de ventas.
  Future<List<Map<String, dynamic>>> getVentasDiariasPorRango(DateTime inicio, DateTime fin) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT strftime('%Y-%m-%d', fecha) AS dia,
             SUM(cantidad) AS unidades,
             SUM(cantidad * precioUnitario) AS valor
      FROM movimiento
      WHERE tipo = 'salida' AND fecha BETWEEN ? AND ?
      GROUP BY dia
      ORDER BY dia ASC
    ''', [inicio.toIso8601String(), fin.toIso8601String()]);
  }

  /// Unidades vendidas agrupadas por hora del día (`hora`, 0-23)
  /// dentro de [inicio]..[fin], de mayor a menor actividad, para
  /// identificar las horas de más ventas.
  Future<List<Map<String, dynamic>>> getVentasPorHoraPorRango(DateTime inicio, DateTime fin) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT CAST(strftime('%H', fecha) AS INTEGER) AS hora,
             SUM(cantidad) AS unidades
      FROM movimiento
      WHERE tipo = 'salida' AND fecha BETWEEN ? AND ?
      GROUP BY hora
      ORDER BY unidades DESC
    ''', [inicio.toIso8601String(), fin.toIso8601String()]);
  }

  /// Ranking de productos del periodo [inicio]..[fin]: `unidadesVendidas`,
  /// `ingresoTotal` y `gananciaEstimada` (ingreso − costo real vía
  /// PEPS) por producto, ordenado por ingreso descendente.
  ///
  /// Cada fila trae las tres métricas, así que de aquí se derivan los
  /// tres rankings (más vendido, mayor ingreso, mayor ganancia)
  /// simplemente reordenando en Dart.
  Future<List<Map<String, dynamic>>> getRankingProductosPorRango(DateTime inicio, DateTime fin) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT p.id, p.nombre,
             SUM(m.cantidad) AS unidadesVendidas,
             SUM(m.cantidad * m.precioUnitario) AS ingresoTotal,
             SUM(m.cantidad * m.precioUnitario) - SUM(m.cantidad * l.costoUnitario) AS gananciaEstimada
      FROM movimiento m
      JOIN lote l ON m.loteId = l.id
      JOIN producto p ON m.productoId = p.id
      WHERE m.tipo = 'salida' AND m.fecha BETWEEN ? AND ?
      GROUP BY p.id
      ORDER BY ingresoTotal DESC
    ''', [inicio.toIso8601String(), fin.toIso8601String()]);
  }

  /// Valor total del inventario actual: cantidad restante × costo real
  /// de cada lote, sumado sobre todos los productos activos. No está
  /// acotado por rango de fechas: es una fotografía del momento en que
  /// se genera el informe.
  Future<double> getValorInventarioActual() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(l.cantidad * l.costoUnitario) AS total
      FROM lote l
      JOIN producto p ON l.productoId = p.id
      WHERE p.activo = 1
    ''');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Productos activos con stock por debajo de su mínimo, como
  /// fotografía del momento actual (no depende del rango del informe).
  /// Cada fila es la misma de [getProductosConStockBatch].
  Future<List<Map<String, dynamic>>> getProductosStockBajoActual() async {
    final filas = await getProductosConStockBatch();
    return filas.where((f) {
      if ((f['activo'] as int) != 1) return false;
      final stock = (f['stockActual'] as num).toInt();
      final minimo = f['stockMinimo'] as int;
      return stock < minimo;
    }).toList();
  }

  /// Fecha de la primera venta registrada, o `null` si aún no hay ventas.
  Future<DateTime?> getFechaPrimeraVenta() async {
    final db = await database;
    final r = await db.rawQuery(
      "SELECT MIN(fecha) AS primera FROM movimiento WHERE tipo = 'salida'",
    );
    final v = r.first['primera'] as String?;
    return v == null ? null : DateTime.tryParse(v);
  }

  /// Unidades vendidas de un único producto dentro de [inicio]..[fin].
  /// Más liviana que [getRankingProductosPorRango] cuando solo interesa
  /// un producto puntual (ej. justo tras registrar una venta).
  Future<double> getUnidadesVendidasProducto(int productoId, DateTime inicio, DateTime fin) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(cantidad) AS total
      FROM movimiento
      WHERE productoId = ? AND tipo = 'salida' AND fecha BETWEEN ? AND ?
    ''', [productoId, inicio.toIso8601String(), fin.toIso8601String()]);
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ===========================================================
  // 10. MANTENIMIENTO
  // ===========================================================

  /// Borra TODOS los datos de la app (conteos, movimientos, lotes y
  /// productos), dejando el esquema intacto. Es irreversible.
  ///
  /// Se borra en orden inverso a las dependencias (primero las tablas
  /// que referencian a otras) y dentro de una transacción, para que un
  /// fallo a medias no deje la base de datos inconsistente.
  Future<void> resetearBaseDeDatos() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('conteo_fisico');
      await txn.delete('movimiento');
      await txn.delete('lote');
      await txn.delete('producto');
    });
  }
}