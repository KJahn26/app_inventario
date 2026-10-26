# inventario_app

A new Flutter project.

App Android local de gestión de inventario con método **PEPS** (Primeras Entradas, Primeras Salidas), pensada para pequeños comercios con productos perecederos. Funciona 100% sin conexión a internet: todos los datos se guardan en una base de datos SQLite dentro del propio dispositivo.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Características

- Control de stock por lotes con método PEPS (costo real, no promediado).
- Alertas de stock bajo: visuales y mediante notificación del sistema.
- Resumen financiero (gasto en reposición, ventas, costo de lo vendido, ganancia), filtrable por mes, trimestre o total acumulado.
- Gráficas de ventas por producto (mensual, trimestral, anual).
- Fotografía de productos, productos activos/descontinuados sin pérdida de historial.
- Exportación del inventario completo a una hoja de cálculo (.xlsx).

## Requisitos

- Flutter SDK ^3.19.0
- Android Studio con un emulador configurado (API 29 o superior recomendado)
- Visual Studio Code con las extensiones de Flutter y Dart (opcional, cualquier editor compatible con Flutter funciona)

## Instalación y ejecución

```bash
flutter pub get
flutter run
```

Para verificar que el entorno esté correctamente configurado:
```bash
flutter doctor
```
