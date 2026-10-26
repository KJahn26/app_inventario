import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Maneja la selección y persistencia local de las fotos de producto.
///
/// `image_picker` solo entrega una ruta temporal al archivo elegido,
/// que el sistema operativo puede borrar en cualquier momento (es
/// una copia de trabajo, no el almacenamiento definitivo). Por eso
/// este servicio copia la imagen al directorio propio de la app
/// antes de guardar la ruta en [Producto.imagenPath], garantizando
/// que la foto siga disponible aunque el usuario borre la imagen
/// original de su galería.
class ImagenService {
  static final ImagePicker _picker = ImagePicker();

  /// Abre el selector de imágenes de la galería, copia la imagen
  /// elegida al almacenamiento privado de la app (comprimida a un
  /// ancho máximo de 800px y calidad 80, para no acumular fotos
  /// pesadas sin necesidad) y devuelve la ruta final ya persistida.
  ///
  /// Devuelve `null` si el usuario cierra el selector sin elegir
  /// ninguna imagen.
  static Future<String?> seleccionarYGuardarImagen() async {
    final XFile? archivo = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 80,
    );

    if (archivo == null) return null;

    final directorioApp = await getApplicationDocumentsDirectory();
    final nombreArchivo =
        'producto_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final rutaDestino = '${directorioApp.path}/$nombreArchivo';

    final archivoOriginal = File(archivo.path);
    await archivoOriginal.copy(rutaDestino);

    return rutaDestino;
  }

  /// Elimina del almacenamiento el archivo de imagen en [path], si
  /// existe. No lanza error si [path] es `null` o el archivo ya no
  /// existe, pensado para usarse de forma segura tanto al borrar un
  /// producto como al reemplazar su foto por una nueva (evitando
  /// dejar imágenes huérfanas ocupando espacio).
  static Future<void> eliminarImagen(String? path) async {
    if (path == null) return;
    final archivo = File(path);
    if (await archivo.exists()) {
      await archivo.delete();
    }
  }
}