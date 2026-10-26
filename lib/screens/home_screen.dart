import 'package:flutter/material.dart';
import 'screensProduct/lista_productos_screen.dart';
import 'screensHistory/historial_screen.dart';
import 'screensDashboard/oportunidades_screen.dart';
import 'screensProduct/comando_voz_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      titulo: 'Inventario Para tu negocio',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            
            children: [
              SizedBox(height: 50),
              Text(
                "¡Bienvenido! \n emprendedor de Estanzuela",
                style: AppText.cuerpo(size: 20),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 5),

              Image.asset(
                'assets/images/icon.png',
                width: 110,
                height: 110,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 5),

              Text(
                "administra tu inventario",
                style: AppText.cuerpo(size: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              _BotonInicio(
                texto: 'Lista de productos',
                icono: Icons.inventory_2_outlined,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ListaProductosScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),

              _BotonInicio(
                texto: 'Historial',
                icono: Icons.receipt_long_outlined,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HistorialScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 10),
              _BotonInicio(
                texto: 'Oportunidades',
                icono: Icons.lightbulb_outline,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OportunidadesScreen()),
                  );
                },
              ),

              const SizedBox(height: 10),
              _BotonInicio(
                texto: 'Comando de voz',
                icono: Icons.mic_outlined,
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ComandoVozScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonInicio extends StatelessWidget {
  final String texto;
  final IconData icono;
  final VoidCallback onPressed;

  const _BotonInicio({
    required this.texto,
    required this.icono,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 90,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.verde, width: 2),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 28, color: Colors.black),
            const SizedBox(height: 4),
            Text(texto, style: AppText.tituloSeccion(color: Colors.black)),
          ],
        ),
      ),
    );
  }
}