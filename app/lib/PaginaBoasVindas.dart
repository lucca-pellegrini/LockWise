import 'package:flutter/material.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'PaginaLogin.dart';
import 'PaginaCadastro.dart';
import 'dart:ui';
import 'models/AssetPreloader.dart';

class BoasVindas extends StatefulWidget {
  const BoasVindas({super.key});

  @override
  State<BoasVindas> createState() => _BoasVindasState();
}

class _BoasVindasState extends State<BoasVindas> {
  final introKey = GlobalKey<IntroductionScreenState>();
  bool _assetsReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await AssetPreloader.preloadAll(context);
      if (mounted) setState(() => _assetsReady = true);
    });
  }

  Widget _buildImage(String assetName, [double width = 400]) {
    return Image.asset('images/$assetName', width: width);
  }

  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    const bodyStyle = TextStyle(fontSize: 19.0);

    const pageDecoration = PageDecoration(
      pageColor: Colors.transparent,
      imagePadding: EdgeInsets.zero,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('images/Fundo8.jpg'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.13),
                  BlendMode.darken,
                ),
              ),
            ),
          ),

          IntroductionScreen(
            key: introKey,
            globalBackgroundColor: Color.fromARGB(0, 3, 21, 119),

            pages: [
              PageViewModel(
                title: '',
                bodyWidget: GlassCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 100),
                      _buildImage('BemVindo.png'),
                      const SizedBox(height: 40),
                      const Text(
                        "Bem-vindo ao LockWise",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 25),
                      Text(
                        "A maneira mais fácil e segura de gerenciar suas fechaduras inteligentes.",
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                decoration: const PageDecoration(
                  pageColor: Colors.transparent,
                  imagePadding: EdgeInsets.zero,
                  contentMargin: EdgeInsets.zero,
                ),
              ),

              PageViewModel(
                title: '',
                bodyWidget: GlassCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 35),
                      _buildImage('SemChave.png'),
                      const SizedBox(height: 0),
                      const Text(
                        "Conectividade Simplificada",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 25),
                      Text(
                        "Conecte suas fechaduras ao aplicativo e nao necessite mais de chaves.",
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                decoration: pageDecoration.copyWith(
                  pageColor: Colors.transparent,
                  imagePadding: EdgeInsets.zero,
                  contentMargin: EdgeInsets.zero,
                ),
              ),

              PageViewModel(
                title: '',
                bodyWidget: GlassCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 35),
                      _buildImage('Desbloqueie.png'),
                      const SizedBox(height: 0),
                      const Text(
                        "Controle Total",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 25),
                      Text(
                        "Tranque e destranque suas portas remotamente, de qualquer lugar.",
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                decoration: pageDecoration.copyWith(
                  pageColor: Colors.transparent,
                  imagePadding: EdgeInsets.zero,
                  contentMargin: EdgeInsets.zero,
                ),
              ),

              PageViewModel(
                title: '',
                bodyWidget: GlassCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 35),
                      _buildImage('Compartilhe.png'),
                      const SizedBox(height: 0),
                      const Text(
                        "Acesso Compartilhado",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 25),
                      Text(
                        "Compartilhe o acesso com familiares e amigos com apenas alguns toques.",
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                decoration: pageDecoration.copyWith(
                  pageColor: Colors.transparent,
                  imagePadding: EdgeInsets.zero,
                  contentMargin: EdgeInsets.zero,
                ),
              ),

              PageViewModel(
                title: '',
                bodyWidget: GlassCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 28),
                      _buildImage('Notificacao.png'),
                      const SizedBox(height: 0),
                      const Text(
                        "Segurança em Primeiro Lugar",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 25),
                      Text(
                        "Receba notificações instantâneas sobre atividades suspeitas.",
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                decoration: pageDecoration.copyWith(
                  pageColor: Colors.transparent,
                  imagePadding: EdgeInsets.zero,
                  contentMargin: EdgeInsets.zero,
                ),
              ),

              PageViewModel(
                // última página (botões) substitui enquanto carrega
                title: '',
                bodyWidget: GlassCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 150),
                      const Text(
                        "Comece Agora",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 35),
                      Text(
                        _assetsReady
                            ? "Crie sua conta e configure sua primeira fechadura LockWise em minutos."
                            : "Carregando recursos...",
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 50),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _assetsReady
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const LoginPage(),
                                    ),
                                  );
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            textStyle: const TextStyle(fontSize: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _assetsReady
                              ? const Text('Fazer Login')
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Carregando...'),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 25),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _assetsReady
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const Cadastro(),
                                    ),
                                  );
                                }
                              : null,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            textStyle: const TextStyle(fontSize: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Criar Conta'),
                        ),
                      ),
                    ],
                  ),
                ),

                decoration: PageDecoration(
                  pageColor: Colors.transparent,
                  imagePadding: EdgeInsets.zero,
                  contentMargin: EdgeInsets.zero,
                ),
              ),
            ],

            onSkip: () => introKey.currentState?.animateScroll(5),

            onChange: (index) {
              setState(() {
                _currentPage = index;
              });
            },

            showSkipButton: _currentPage != 5,
            skipOrBackFlex: 0,
            nextFlex: 0,
            showDoneButton: false,

            skip: const Text(
              'Pular',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            next: const Icon(Icons.arrow_forward, color: Colors.white),
            back: const Icon(Icons.arrow_back, color: Colors.white),
            curve: Curves.fastLinearToSlowEaseIn,
            controlsMargin: const EdgeInsets.all(16),
            controlsPadding: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 4.0),

            dotsDecorator: const DotsDecorator(
              size: Size(10.0, 40.0),
              color: Colors.white,
              activeSize: Size(22.0, 10.0),
              activeColor: Colors.black54,
              activeShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(25.0)),
              ),
            ),

            dotsContainerDecorator: ShapeDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.19),
                  Colors.white.withOpacity(0.13),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8.0)),
                side: BorderSide(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
              ),
            ),
          ),
        ],
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
                      Colors.white.withOpacity(0.25),
                      Colors.white.withOpacity(0.1),
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

