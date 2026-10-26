import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import '../../db/database_helper.dart';
import '../../models/producto.dart';

/// Resultado de una operación de importación, para mostrarle al
/// usuario un resumen claro de lo que se hizo.
class ImportResultado {
  final int productosCreados;
  final int productosReutilizados;
  final int movimientosImportados;
  final int movimientosOmitidos;
  final bool cancelado;

  ImportResultado({
    this.productosCreados = 0,
    this.productosReutilizados = 0,
    this.movimientosImportados = 0,
    this.movimientosOmitidos = 0,
    this.cancelado = false,
  });
}

/// Reconstruye productos, lotes y movimientos a partir de un archivo
/// .xlsx generado por [ExportService].
///
/// El archivo exportado no guarda los lotes directamente (solo
/// movimientos agregados), así que la importación los reconstruye
/// reproduciendo cada movimiento en orden cronológico: las entradas
/// recrean lotes nuevos vía [DatabaseHelper.registrarEntrada], y las
/// salidas se vuelven a aplicar con [DatabaseHelper.registrarVentaPEPS],
/// que descuenta de esos lotes siguiendo la misma lógica PEPS original.
class ImportService {
  static Future<ImportResultado> importarDesdeExcel() async {
    final resultadoArchivo = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true, // trae los bytes directamente, evita problemas de rutas en Android
    );

    if (resultadoArchivo == null || resultadoArchivo.files.single.bytes == null) {
      return ImportResultado(cancelado: true);
    }

    final bytes = resultadoArchivo.files.single.bytes!;
    final excelFile = Excel.decodeBytes(bytes);

    final db = DatabaseHelper.instance;

    final hojaProductos = excelFile['Productos'];
    final hojaMovimientos = excelFile['Movimientos'];

    // ---- 1. Productos: reutiliza por nombre si ya existe, si no, crea uno nuevo ----
    final productosExistentes = await db.getProductos();
    final Map<String, int> nombreAId = {
      for (final p in productosExistentes) p.nombre: p.id!,
    };

    int productosCreados = 0;
    int productosReutilizados = 0;

    // Fila 0 es encabezado: ID_Producto, Nombre, Unidad, Stock_Actual, Stock_Minimo, Estado
    for (int fila = 1; fila < hojaProductos.maxRows; fila++) {
      final row = hojaProductos.row(fila);
      if (row.isEmpty || row[1]?.value == null) continue; // fila vacía

      final nombre = row[1]!.value.toString();
      final unidad = row[2]?.value?.toString() ?? 'unidad';
      final stockMinimo = _aEntero(row[4]?.value) ?? 0;
      final estado = row[5]?.value?.toString() ?? 'Activo';

      if (nombreAId.containsKey(nombre)) {
        productosReutilizados++;
        continue; // ya existe en este dispositivo, no se duplica
      }

      final nuevoId = await db.insertProducto(Producto(
        nombre: nombre,
        unidad: unidad,
        stockMinimo: stockMinimo,
        activo: estado != 'Descontinuado',
      ));
      nombreAId[nombre] = nuevoId;
      productosCreados++;
    }

    // ---- 2. Movimientos: se leen, se ordenan por fecha y se reaplican ----
    final List<_FilaMovimiento> filasMovimientos = [];

    // Fila 0 es encabezado: Fecha, ID_Producto, Producto, Tipo, Cantidad, Precio_Unitario, Total
    for (int fila = 1; fila < hojaMovimientos.maxRows; fila++) {
      final row = hojaMovimientos.row(fila);
      if (row.isEmpty || row[2]?.value == null) continue;

      final fechaTexto = row[0]?.value?.toString();
      final nombreProducto = row[2]!.value.toString();
      final tipo = row[3]?.value?.toString().toLowerCase();
      final cantidad = _aEntero(row[4]?.value);
      final precio = _aDouble(row[5]?.value);

      if (fechaTexto == null || cantidad == null || precio == null) continue;

      final fecha = DateTime.tryParse(fechaTexto);
      if (fecha == null) continue;

      filasMovimientos.add(_FilaMovimiento(
        fecha: fecha,
        nombreProducto: nombreProducto,
        esEntrada: tipo == 'entrada',
        cantidad: cantidad,
        precio: precio,
      ));
    }

    filasMovimientos.sort((a, b) => a.fecha.compareTo(b.fecha));

    int movimientosImportados = 0;
    int movimientosOmitidos = 0;

    for (final m in filasMovimientos) {
      final productoId = nombreAId[m.nombreProducto];
      if (productoId == null) {
        movimientosOmitidos++;
        continue;
      }

      if (m.esEntrada) {
        await db.registrarEntrada(
          productoId: productoId,
          cantidad: m.cantidad,
          costoUnitario: m.precio,
        );
        movimientosImportados++;
      } else {
        final exito = await db.registrarVentaPEPS(
          productoId: productoId,
          cantidadVendida: m.cantidad,
          precioVenta: m.precio,
        );
        if (exito) {
          movimientosImportados++;
        } else {
          // No había stock suficiente reconstruido para esta salida
          // (puede pasar si el archivo está incompleto o corrupto).
          movimientosOmitidos++;
        }
      }
    }

    return ImportResultado(
      productosCreados: productosCreados,
      productosReutilizados: productosReutilizados,
      movimientosImportados: movimientosImportados,
      movimientosOmitidos: movimientosOmitidos,
    );
  }

  static int? _aEntero(dynamic valorCelda) {
    if (valorCelda == null) return null;
    if (valorCelda is IntCellValue) return valorCelda.value;
    if (valorCelda is DoubleCellValue) return valorCelda.value.toInt();
    return int.tryParse(valorCelda.toString());
  }

  static double? _aDouble(dynamic valorCelda) {
    if (valorCelda == null) return null;
    if (valorCelda is DoubleCellValue) return valorCelda.value;
    if (valorCelda is IntCellValue) return valorCelda.value.toDouble();
    return double.tryParse(valorCelda.toString());
  }
}

class _FilaMovimiento {
  final DateTime fecha;
  final String nombreProducto;
  final bool esEntrada;
  final int cantidad;
  final double precio;

  _FilaMovimiento({
    required this.fecha,
    required this.nombreProducto,
    required this.esEntrada,
    required this.cantidad,
    required this.precio,
  });
}