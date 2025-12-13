import 'package:flutter/material.dart';
import 'PaginaSobre.dart';
import 'dart:ui';
import 'LocalService.dart';
import 'PaginaLogin.dart';
import 'PaginaConvite.dart';
import 'PaginaConta.dart';

class Config extends StatefulWidget {
  const Config({super.key});

  @override
  State<Config> createState() => _ConfigState();
}

class _ConfigState extends State<Config> {
  bool _isLoading = true;
  Map<String, dynamic>? usuario;

  @override
  void initState() {
    super.initState();
    _carregarUsuario();
  }

  Future<void> _carregarUsuario() async {
    try {
      // Adicione um print para debug
      final user = await LocalService.getUsuarioLogado();
      print('Usuario carregado: $user'); // Debug

      setState(() {
        usuario = user;
        _isLoading = false;
      });
    } catch (e) {
      print('Erro ao carregar usuario: $e'); // Debug
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Column(
              children: [
                CircleAvatar(
                  radius: 55,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 60, color: Colors.grey),
                ),
                const SizedBox(height: 25),
                _isLoading
                    ? CircularProgressIndicator(color: Colors.blueAccent)
                    : Text(
                        usuario != null ? usuario!['nome'] : 'Usuário',
                        style: TextStyle(fontSize: 20, color: Colors.white),
                      ),
                const SizedBox(height: 5),
              ],
            ),

            const SizedBox(height: 30),

            _ConfigButton(
              icon: Icons.person,
              label: 'Conta',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PaginaConta()),
                );
              },
            ),

            _ConfigButton(
              icon: Icons.mail,
              label: 'Convites',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PaginaConvites(),
                  ),
                );
              },
            ),

            _ConfigButton(
              icon: Icons.info_outline,
              label: 'Sobre',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const Sobre()),
                );
              },
            ),

            _ConfigButton(
              icon: Icons.logout,
              label: 'Sair',
              onPressed: () async {
                await LocalService.logout();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ConfigButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withOpacity(0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        icon: Icon(icon, size: 24),
        label: Align(alignment: Alignment.centerLeft, child: Text(label)),
        onPressed: onPressed,
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsets? padding;
  final double borderRadius;
  final double blurIntensity;
  final List<Color>? gradientColors;

  const GlassCard({
    Key? key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.borderRadius = 20.0,
    this.blurIntensity = 10.0,
    this.gradientColors,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),

        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blurIntensity,
            sigmaY: blurIntensity,
          ),

          child: Container(
            width: width ?? MediaQuery.of(context).size.width * 0.9,
            height: height ?? MediaQuery.of(context).size.height * 0.78,
            padding: padding ?? const EdgeInsets.all(30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors:
                    gradientColors ??
                    [
                      Colors.blueAccent.withOpacity(0.3),
                      Colors.blueAccent.withOpacity(0.1),
                    ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),

            child: child,
          ),
        ),
      ),
    );
  }
}
