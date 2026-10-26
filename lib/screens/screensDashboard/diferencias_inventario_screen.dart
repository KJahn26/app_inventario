import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/empty_state.dart';

class DiferenciasInventarioScreen extends StatefulWidget {
  const DiferenciasInventarioScreen({super.key});

  @override
  State<DiferenciasInventarioScreen> createState() => _DiferenciasInventarioScreenState();
}

class _DiferenciasInventarioScreenState extends State<DiferenciasInventarioScreen> {
  late Future<List<Map<String, dynamic>>> _diferenciasFuture;

  @override
  void initState() {
    super.initState();
    _diferenciasFuture = DatabaseHelper.instance.getUltimasDiferenciasInventario();
  }

  Future<void> _registrarIncidente(BuildContext context, int conteoId, bool sobrante) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          sobrante ? 'Registrar ganancia' : 'Registrar pérdida',
          style: AppText.tituloSeccion(),
        ),
        content: Text(
          sobrante
              ? 'El sobrante se sumará al stock como una ganancia de inventario. Esta acción quedará en el historial.'
              : 'El faltante se descontará del stock como una pérdida de inventario. Esta acción quedará en el historial.',
          style: AppText.cuerpo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: AppText.cuerpo()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Confirmar', style: AppText.cuerpo()),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    await DatabaseHelper.instance.registrarIncidenteInventario(conteoId);

    if (!mounted) return;
    setState(() {
      _diferenciasFuture = DatabaseHelper.instance.getUltimasDiferenciasInventario();
    });

    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Incidente registrado en el historial', style: AppText.cuerpo())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Diferencias de inventario',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _diferenciasFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data ?? [];

          if (items.isEmpty) {
            return const EmptyState(
              icono: Icons.fact_check_outlined,
              mensaje: 'No hay diferencias pendientes de revisión.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final c = items[index];
              final diferencia = c['diferencia'] as int;
              final sobrante = diferencia > 0;

              return ListTile(
                contentPadding: const EdgeInsets.all(8),
                leading: Icon(
                  sobrante ? Icons.arrow_upward : Icons.arrow_downward,
                  color: sobrante ? Colors.blue : Colors.red,
                ),
                title: Text(c['nombre'] as String, style: AppText.cuerpo(size: 18)),
                subtitle: Text(
                  'Sistema: ${c['cantidadSistema']} \nContado: ${c['cantidadContada']} ${c['unidad']}',
                  style: AppText.cuerpo(),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      sobrante ? '+$diferencia' : '$diferencia',
                      style: AppText.cuerpo(
                        size: 16,
                        color: sobrante ? Colors.blue : Colors.red,
                        peso: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => _registrarIncidente(context, c['id'] as int, sobrante),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.withAlpha(15), // Fondo sutil pero visible
                        foregroundColor: Colors.orange, // Color del texto/ícono
                        elevation: 0, // Sin sombra pesada, estilo plano moderno
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8), // Esquinas redondeadas
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 6),
                          Text(
                            sobrante ? 'Registrar ganancia' : 'Registrar pérdida',
                            style: AppText.cuerpo(
                              size: 14,
                              color: Colors.orange,
                              peso: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}