import '../../models/producto.dart';

enum TipoComandoVoz { venta, entrada, consultaStock, desconocido }

class ComandoVoz {
  final TipoComandoVoz tipo;
  final String nombreProductoDicho;
  final int? cantidad;
  final double? precio;

  ComandoVoz({
    required this.tipo,
    required this.nombreProductoDicho,
    this.cantidad,
    this.precio,
  });
}

/// Convierte números dichos en palabras ("ocho", "veinticinco", "mil
/// quinientos") a su valor numérico. Cubre los casos más comunes al
/// dictar cantidades y precios; no pretende ser un parser exhaustivo
/// de todo el español numérico.
class _NumeroEnPalabras {
  static const _unidades = {
    'cero': 0, 'un': 1, 'uno': 1, 'una': 1, 'dos': 2, 'tres': 3, 'cuatro': 4,
    'cinco': 5, 'seis': 6, 'siete': 7, 'ocho': 8, 'nueve': 9, 'diez': 10,
    'once': 11, 'doce': 12, 'trece': 13, 'catorce': 14, 'quince': 15,
    'dieciseis': 16, 'diecisiete': 17, 'dieciocho': 18, 'diecinueve': 19,
    'veinte': 20, 'veintiuno': 21, 'veintidos': 22, 'veintitres': 23,
    'veinticuatro': 24, 'veinticinco': 25, 'veintiseis': 26, 'veintisiete': 27,
    'veintiocho': 28, 'veintinueve': 29,
  };
  static const _decenas = {
    'treinta': 30, 'cuarenta': 40, 'cincuenta': 50, 'sesenta': 60,
    'setenta': 70, 'ochenta': 80, 'noventa': 90,
  };
  static const _centenas = {
    'cien': 100, 'ciento': 100, 'doscientos': 200, 'trescientos': 300,
    'cuatrocientos': 400, 'quinientos': 500, 'seiscientos': 600,
    'setecientos': 700, 'ochocientos': 800, 'novecientos': 900,
  };

  static bool esTokenNumerico(String tok) =>
      _unidades.containsKey(tok) || _decenas.containsKey(tok) ||
      _centenas.containsKey(tok) || tok == 'mil' || tok == 'y';

  /// Convierte una secuencia de palabras numéricas ya identificadas
  /// (ej. ["mil", "quinientos"]) a su valor entero.
  static int? valorDeTokens(List<String> tokens) {
    if (tokens.isEmpty) return null;
    int total = 0;
    int actual = 0;
    bool huboAlgo = false;

    for (final tok in tokens) {
      if (tok == 'y') continue;
      if (_unidades.containsKey(tok)) {
        actual += _unidades[tok]!;
        huboAlgo = true;
      } else if (_decenas.containsKey(tok)) {
        actual += _decenas[tok]!;
        huboAlgo = true;
      } else if (_centenas.containsKey(tok)) {
        actual += _centenas[tok]!;
        huboAlgo = true;
      } else if (tok == 'mil') {
        actual = (actual == 0 ? 1 : actual) * 1000;
        total += actual;
        actual = 0;
        huboAlgo = true;
      }
    }
    return huboAlgo ? total + actual : null;
  }
}

class _NumeroEncontrado {
  final int valor;
  final int fin; // índice del token siguiente al número (exclusive)
  _NumeroEncontrado(this.valor, this.fin);
}

/// Interpreta frases dictadas como comandos estructurados (venta,
/// entrada, consulta de stock).
///
/// En vez de exigir una frase exacta ("vender X Y a Z"), busca el
/// verbo de intención al inicio y luego extrae números dondequiera
/// que aparezcan en el resto de la frase (en dígitos o en palabras),
/// sin depender de una preposición exacta entre cantidad y precio —
/// así "hasta", "a", "por" o ninguna palabra conectora funcionan
/// igual. El nombre del producto es lo que queda entre esos números,
/// y se resuelve contra el catálogo por coincidencia difusa.
class VoiceParserService {
  static const _fillersConsulta = {
    'cuanto', 'cuantos', 'cuanta', 'cuantas', 'stock', 'inventario',
    'queda', 'quedan', 'hay', 'tengo', 'de', 'del',
  };
  static const _fillersProducto = {'a', 'por', 'hasta', 'en', 'de', 'cada', 'c/u', 'el', 'la', 'los', 'las'};

  static ComandoVoz interpretar(String texto) {
    final tokens = _normalizar(texto).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) {
      return ComandoVoz(tipo: TipoComandoVoz.desconocido, nombreProductoDicho: texto);
    }

    final intent = _detectarIntent(tokens);

    if (intent == TipoComandoVoz.consultaStock) {
      final restantes = tokens.where((t) => !_fillersConsulta.contains(t)).toList();
      final nombre = restantes.join(' ').trim();
      return ComandoVoz(
        tipo: nombre.isEmpty ? TipoComandoVoz.desconocido : TipoComandoVoz.consultaStock,
        nombreProductoDicho: nombre,
      );
    }

    if (intent == TipoComandoVoz.venta || intent == TipoComandoVoz.entrada) {
      final restoDesde = _saltarVerbo(tokens);
      final resto = tokens.sublist(restoDesde);
      final numeros = _extraerNumeros(resto);

      if (numeros.isEmpty) {
        return ComandoVoz(tipo: TipoComandoVoz.desconocido, nombreProductoDicho: resto.join(' '));
      }

      final cantidad = numeros.first.valor;
      final inicioProducto = numeros.first.fin;
      final finProducto = numeros.length > 1 ? _inicioDelNumero(resto, numeros[1], inicioProducto) : resto.length;
      final precio = numeros.length > 1 ? numeros[1].valor.toDouble() : null;

      var nombreTokens = resto.sublist(inicioProducto, finProducto);
      while (nombreTokens.isNotEmpty && _fillersProducto.contains(nombreTokens.first)) {
        nombreTokens = nombreTokens.sublist(1);
      }
      while (nombreTokens.isNotEmpty && _fillersProducto.contains(nombreTokens.last)) {
        nombreTokens = nombreTokens.sublist(0, nombreTokens.length - 1);
      }

      return ComandoVoz(
        tipo: intent,
        cantidad: cantidad,
        precio: precio,
        nombreProductoDicho: nombreTokens.join(' ').trim(),
      );
    }

    return ComandoVoz(tipo: TipoComandoVoz.desconocido, nombreProductoDicho: texto);
  }

  static TipoComandoVoz _detectarIntent(List<String> tokens) {
    final w0 = tokens[0];
    if (['vender', 'vende', 'venta'].contains(w0)) return TipoComandoVoz.venta;
    if (['agregar', 'agrega', 'entrada', 'comprar', 'compra'].contains(w0)) return TipoComandoVoz.entrada;
    if (['cuanto', 'cuantos', 'cuanta', 'cuantas'].contains(w0)) return TipoComandoVoz.consultaStock;
    if (w0 == 'registrar' && tokens.length > 1) {
      if (tokens[1] == 'venta') return TipoComandoVoz.venta;
      if (tokens[1] == 'entrada') return TipoComandoVoz.entrada;
    }
    return TipoComandoVoz.desconocido;
  }

  static int _saltarVerbo(List<String> tokens) {
    if (tokens[0] == 'registrar') {
      var i = 2; // "registrar venta/entrada"
      if (i < tokens.length && tokens[i] == 'de') i++;
      return i;
    }
    var i = 1;
    if (i < tokens.length && tokens[i] == 'de') i++;
    return i;
  }

  /// Encuentra todos los números presentes en [tokens], en dígitos o
  /// en palabras, en el orden en que aparecen.
  static List<_NumeroEncontrado> _extraerNumeros(List<String> tokens) {
    final resultados = <_NumeroEncontrado>[];
    int i = 0;
    while (i < tokens.length) {
      final tok = tokens[i];
      final comoDigito = double.tryParse(tok.replaceAll(',', '.'));
      if (comoDigito != null) {
        resultados.add(_NumeroEncontrado(comoDigito.round(), i + 1));
        i++;
        continue;
      }
      if (_NumeroEnPalabras.esTokenNumerico(tok)) {
        int j = i;
        final grupo = <String>[];
        while (j < tokens.length && _NumeroEnPalabras.esTokenNumerico(tokens[j])) {
          grupo.add(tokens[j]);
          j++;
        }
        while (grupo.isNotEmpty && grupo.last == 'y') {
          grupo.removeLast();
          j--;
        }
        final valor = _NumeroEnPalabras.valorDeTokens(grupo);
        if (valor != null) resultados.add(_NumeroEncontrado(valor, j));
        i = j;
        continue;
      }
      i++;
    }
    return resultados;
  }

  static int _inicioDelNumero(List<String> tokens, _NumeroEncontrado numero, int desde) {
    // Busca dónde empieza ese número recorriendo desde [desde].
    for (int k = desde; k < numero.fin; k++) {
      final tok = tokens[k];
      final esNumero = double.tryParse(tok.replaceAll(',', '.')) != null || _NumeroEnPalabras.esTokenNumerico(tok);
      if (esNumero) return k;
    }
    return numero.fin;
  }

  /// Busca el producto cuyo nombre más se parece a [nombreDicho],
  /// usando distancia de Levenshtein.
  static Producto? encontrarProductoMasParecido(String nombreDicho, List<Producto> productos) {
    final dicho = _normalizar(nombreDicho);
    Producto? mejor;
    int mejorDistancia = 999;

    for (final p in productos) {
      final nombre = _normalizar(p.nombre);
      final dist = _distancia(dicho, nombre);
      final umbral = (nombre.length * 0.4).ceil().clamp(1, 6);
      if (dist <= umbral && dist < mejorDistancia) {
        mejor = p;
        mejorDistancia = dist;
      }
    }
    return mejor;
  }

  static String _normalizar(String s) => s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .trim();

  static int _distancia(String a, String b) {
    final m = a.length, n = b.length;
    final d = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    
    for (var i = 0; i <= m; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= n; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final costo = a[i - 1] == b[j - 1] ? 0 : 1;
        d[i][j] = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + costo].reduce((x, y) => x < y ? x : y);
      }
    }
    return d[m][n];
  }
}