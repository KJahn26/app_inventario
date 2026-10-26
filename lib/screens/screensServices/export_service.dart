import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../db/database_helper.dart';

class ExportService {
  static Future<ShareResultStatus> exportarYCompartir() async {
    final db = DatabaseHelper.instance;
    final excelFile = Excel.createExcel();

    // -----------------------------------------------------------------
    // ESTILOS REUTILIZABLES
    // -----------------------------------------------------------------
    // Estilo para Encabezados (Fondo Azul Marino, Texto Blanco, Negrita, Centrado)
    final headerStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#1F4E78'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    // Estilo para Fechas e IDs
    final centerStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Center,
    );

    // Estilo para Moneda / Dinero
    final moneyStyle = CellStyle(
      numberFormat: NumFormat.custom(formatCode: r'Q#,##0.00'),
      horizontalAlign: HorizontalAlign.Right,
    );

    // Estilo para Totales o Resumen (Fondo Gris Claro + Negrita)
    final totalHeaderStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#D9D9D9'),
      bold: true,
    );

    // -----------------------------------------------------------------
    // 1. HOJA: PRODUCTOS (Catálogo optimizado para consulta e importación)
    // -----------------------------------------------------------------
    final hojaProductos = excelFile['Productos'];
    excelFile.delete('Sheet1'); // Eliminar la hoja por defecto

    // Encabezados
    final headersProductos = [
      'ID_Producto',
      'Nombre',
      'Unidad',
      'Stock_Actual',
      'Stock_Minimo',
      'Estado'
    ];

    hojaProductos.appendRow(
      headersProductos.map((h) => TextCellValue(h)).toList(),
    );

    // Aplicar estilo al encabezado
    for (int col = 0; col < headersProductos.length; col++) {
      final cell = hojaProductos.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.cellStyle = headerStyle;
    }

    final productos = await db.getProductosConStockBatch();
    int rowProdIndex = 1;

    for (final p in productos) {
      final esActivo = (p['activo'] as int) == 1;

      hojaProductos.appendRow([
        IntCellValue(p['id'] as int),
        TextCellValue(p['nombre'] as String),
        TextCellValue(p['unidad'] as String),
        IntCellValue((p['stockActual'] as num).toInt()),
        IntCellValue(p['stockMinimo'] as int),
        TextCellValue(esActivo ? 'Activo' : 'Descontinuado'),
      ]);

      // Estilos específicos por celda
      hojaProductos
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowProdIndex))
          .cellStyle = centerStyle;

      // Color condicional para el estado
      hojaProductos
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowProdIndex))
          .cellStyle = CellStyle(
        fontColorHex: esActivo
            ? ExcelColor.fromHexString('#2E75B6')
            : ExcelColor.fromHexString('#A6A6A6'),
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      rowProdIndex++;
    }

    // Ajustar anchos de columna (Aproximados)
    hojaProductos.setColumnWidth(0, 15);
    hojaProductos.setColumnWidth(1, 30);
    hojaProductos.setColumnWidth(2, 15);
    hojaProductos.setColumnWidth(3, 15);
    hojaProductos.setColumnWidth(4, 15);
    hojaProductos.setColumnWidth(5, 18);

    // -----------------------------------------------------------------
    // 2. HOJA: MOVIMIENTOS (Historial de Entradas/Salidas)
    // -----------------------------------------------------------------
    final hojaMovimientos = excelFile['Movimientos'];

    final headersMovimientos = [
      'Fecha',
      'ID_Producto',
      'Producto',
      'Tipo',
      'Cantidad',
      'Precio_Unitario',
      'Total'
    ];

    hojaMovimientos.appendRow(
      headersMovimientos.map((h) => TextCellValue(h)).toList(),
    );

    // Aplicar estilo al encabezado
    for (int col = 0; col < headersMovimientos.length; col++) {
      final cell = hojaMovimientos.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.cellStyle = headerStyle;
    }

    final movimientos = await db.getMovimientosConNombreProducto();
    int rowMovIndex = 1;

    for (final m in movimientos) {
      final cantidad = m['cantidad'] as int;
      final precio = (m['precioUnitario'] as num).toDouble();
      final tipo = m['tipo'] as String;
      final excelRowNumber = rowMovIndex + 1; // Fila en Excel base 1

      hojaMovimientos.appendRow([
        TextCellValue(m['fecha'] as String), // Mantiene formato ISO string
        IntCellValue(m['productoId'] ?? 0), // Importante para reimportar datos
        TextCellValue(m['nombreProducto'] as String),
        TextCellValue(tipo),
        IntCellValue(cantidad),
        DoubleCellValue(precio),
        // Fórmula dinámica de Excel: Multiplica Cantidad * Precio
        FormulaCellValue('E$excelRowNumber*F$excelRowNumber'),
      ]);

      // Aplicar formatos por celda
      hojaMovimientos
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowMovIndex))
          .cellStyle = centerStyle;

      hojaMovimientos
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowMovIndex))
          .cellStyle = centerStyle;

      // Color condicional para tipo de movimiento
      final isEntrada = tipo.toUpperCase() == 'ENTRADA';
      hojaMovimientos
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowMovIndex))
          .cellStyle = CellStyle(
        fontColorHex: isEntrada
            ? ExcelColor.fromHexString('#385723')
            : ExcelColor.fromHexString('#C00000'),
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      // Formato de moneda para Precio Unitario y Total
      hojaMovimientos
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowMovIndex))
          .cellStyle = moneyStyle;

      hojaMovimientos
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowMovIndex))
          .cellStyle = moneyStyle;

      rowMovIndex++;
    }

    // Ancho de columnas
    hojaMovimientos.setColumnWidth(0, 22);
    hojaMovimientos.setColumnWidth(1, 15);
    hojaMovimientos.setColumnWidth(2, 28);
    hojaMovimientos.setColumnWidth(3, 15);
    hojaMovimientos.setColumnWidth(4, 12);
    hojaMovimientos.setColumnWidth(5, 18);
    hojaMovimientos.setColumnWidth(6, 18);

    // -----------------------------------------------------------------
    // 3. HOJA: RESUMEN FINANCIERO
    // -----------------------------------------------------------------
    final hojaResumen = excelFile['Resumen financiero'];
    final resumen = await db.getResumenFinanciero();

    hojaResumen.appendRow([TextCellValue('Concepto'), TextCellValue('Valor')]);

    for (int col = 0; col < 2; col++) {
      hojaResumen
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
          .cellStyle = headerStyle;
    }

    final conceptos = [
      {'nombre': 'Gastado en reposición', 'valor': resumen['totalGastado'] ?? 0.0},
      {'nombre': 'Total en ventas', 'valor': resumen['totalVentas'] ?? 0.0},
      {'nombre': 'Costo de lo vendido', 'valor': resumen['costoVendido'] ?? 0.0},
      {'nombre': 'Ganancia', 'valor': resumen['ganancia'] ?? 0.0},
    ];

    int rowResumenIndex = 1;
    for (final c in conceptos) {
      hojaResumen.appendRow([
        TextCellValue(c['nombre'] as String),
        DoubleCellValue((c['valor'] as num).toDouble()),
      ]);

      // Formatear celda de dinero
      hojaResumen
          .cell(CellIndex.indexByColumnRow(
              columnIndex: 1, rowIndex: rowResumenIndex))
          .cellStyle = moneyStyle;

      // Resaltar la fila de Ganancia
      if (c['nombre'] == 'Ganancia') {
        hojaResumen
            .cell(CellIndex.indexByColumnRow(
                columnIndex: 0, rowIndex: rowResumenIndex))
            .cellStyle = totalHeaderStyle;

        hojaResumen
            .cell(CellIndex.indexByColumnRow(
                columnIndex: 1, rowIndex: rowResumenIndex))
            .cellStyle = CellStyle(
          numberFormat: NumFormat.custom(formatCode: r'Q#,##0.00'),
          horizontalAlign: HorizontalAlign.Right,
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('#E2EFDA'),
        );
      }

      rowResumenIndex++;
    }
    hojaResumen.setColumnWidth(0, 30);
    hojaResumen.setColumnWidth(1, 20);

    // -----------------------------------------------------------------
    // GUARDAR Y COMPARTIR ARCHIVO
    // -----------------------------------------------------------------
    final directorio = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nombreArchivo = 'inventario_respaldo_$timestamp.xlsx';
    final ruta = '${directorio.path}/$nombreArchivo';

    final bytes = excelFile.encode();
    if (bytes == null) {
      throw Exception('Error al codificar el archivo Excel');
    }

    final archivo = File(ruta);
    await archivo.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(ruta)],
      text: 'Respaldo de Inventario en formato Excel (.xlsx)',
    );

    final resultado = await Share.shareXFiles([XFile(ruta)], text: 'Exportacion de inventario');
    return resultado.status;
  }
}