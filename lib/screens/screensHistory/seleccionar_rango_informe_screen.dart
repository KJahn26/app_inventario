import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/primary_button.dart';
import '../screensServices/pdf_report_service.dart';

class SeleccionarRangoInformeScreen extends StatefulWidget {
  const SeleccionarRangoInformeScreen({super.key});

  @override
  State<SeleccionarRangoInformeScreen> createState() =>
      _SeleccionarRangoInformeScreenState();
}

class _SeleccionarRangoInformeScreenState
    extends State<SeleccionarRangoInformeScreen> {
  DateTimeRange? _rangoSeleccionado;
  bool _generando = false;

  Future<void> _elegirRango() async {
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(ahora.year - 5),
      lastDate: ahora,
      initialDateRange: _rangoSeleccionado ??
          DateTimeRange(
            start: DateTime(ahora.year, ahora.month, 1),
            end: ahora,
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.verde),
          ),
          child: child!,
        );
      },
    );

    if (rango != null) {
      setState(() => _rangoSeleccionado = rango);
    }
  }

  void _elegirAtajo(int dias) {
    final ahora = DateTime.now();
    setState(() {
      _rangoSeleccionado = DateTimeRange(
        start: ahora.subtract(Duration(days: dias)),
        end: ahora,
      );
    });
  }

  void _elegirMesActual() {
    final ahora = DateTime.now();
    setState(() {
      _rangoSeleccionado = DateTimeRange(
        start: DateTime(ahora.year, ahora.month, 1),
        end: ahora,
      );
    });
  }

  String _formatearFecha(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  Future<void> _generarInforme() async {
    if (_rangoSeleccionado == null) return;

    setState(() => _generando = true);
    try {
      await PdfReportService.generarYCompartir(
        inicio: _rangoSeleccionado!.start,
        fin: _rangoSeleccionado!.end,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al generar el informe: $e', style: AppText.cuerpo())),
        );
      }
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Informe del negocio',
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Elige el periodo que quieres analizar.',
              style: AppText.secundario(size: 14),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ChipAtajo(texto: 'Últimos 7 días', onTap: () => _elegirAtajo(7)),
                _ChipAtajo(texto: 'Últimos 30 días', onTap: () => _elegirAtajo(30)),
                _ChipAtajo(texto: 'Este mes', onTap: _elegirMesActual),
                _ChipAtajo(texto: 'Últimos 90 días', onTap: () => _elegirAtajo(90)),
              ],
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _elegirRango,
              icon: const Icon(Icons.date_range),
              label: Text('Elegir rango personalizado', style: AppText.cuerpo(color: AppColors.verde)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: AppColors.verde,
              ),
            ),
            const SizedBox(height: 20),
            if (_rangoSeleccionado != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.verde.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.verde.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_available, color: AppColors.verde),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Del ${_formatearFecha(_rangoSeleccionado!.start)} al ${_formatearFecha(_rangoSeleccionado!.end)}',
                        style: AppText.cuerpo(peso: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            PrimaryButton(
              texto: 'Generar informe',
              cargando: _generando,
              onPressed: _rangoSeleccionado == null ? null : _generarInforme,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipAtajo extends StatelessWidget {
  final String texto;
  final VoidCallback onTap;

  const _ChipAtajo({required this.texto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(texto, style: AppText.cuerpo(size: 13)),
      onPressed: onTap,
      backgroundColor: AppColors.verde.withAlpha(20),
      labelStyle: AppText.cuerpo(),
    );
  }
}