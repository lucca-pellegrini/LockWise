import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'dart:ui';

class Sobre extends StatelessWidget {
  const Sobre({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('images/Fundo9.jpg'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.0),
            BlendMode.srcOver,
          ),
        ),
      ),

      child: Scaffold(
        backgroundColor: Colors.transparent,

        appBar: AppBar(
          title: Text('Sobre', style: TextStyle(color: Colors.white)),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          iconTheme: IconThemeData(size: 30.0),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ),

        body: content(context), // Passando context para calcular altura
      ),
    );
  }
}

Widget content(BuildContext context) {
  // Lista com conteúdo específico para cada slide
  final List<SlideData> slidesData = [
    SlideData(
      title: "O que é o LockWise?",
      description:
          "O LockWise controla suas fechaduras de forma inteligente, segura, e prática",
      color: Colors.blue,
      icon: Icons.home_outlined,
      gradientColors: [
        Colors.blue.withOpacity(0.30),
        Colors.blue.withOpacity(0.10),
      ],
    ),
    SlideData(
      title: "Comando de Voz",
      description: "Abra e feche as portas usando comandos de voz inteligentes",
      color: Colors.orange,
      icon: Icons.mic,
      gradientColors: [
        Colors.blue.withOpacity(0.30),
        Colors.blue.withOpacity(0.10),
      ],
    ),
    SlideData(
      title: "Monitoramento 24/7",
      description:
          "Receba notificações em tempo real sobre acessos e estado das fechaduras",
      color: Colors.red,
      icon: Icons.notifications_outlined,
      gradientColors: [
        Colors.blue.withOpacity(0.30),
        Colors.blue.withOpacity(0.10),
      ],
    ),
    SlideData(
      title: "Responsáveis pelo App",
      description: "Amanda Canizela, Ariel Inácio, Lucca Pellegrini",
      color: Colors.blueGrey,
      icon: Icons.code_outlined,
      gradientColors: [
        Colors.blue.withOpacity(0.30),
        Colors.blue.withOpacity(0.10),
      ],
    ),
    SlideData(
      title: "Responsáveis pela Fechadura",
      description: "Felipe de Mello, Lucca Pellegrini",
      color: Colors.pinkAccent,
      icon: Icons.build_outlined,
      gradientColors: [
        Colors.blue.withOpacity(0.30),
        Colors.blue.withOpacity(0.10),
      ],
    ),
  ];

  // Calcula a altura disponível
  double availableHeight =
      MediaQuery.of(context).size.height -
      AppBar().preferredSize.height -
      MediaQuery.of(context).padding.top -
      MediaQuery.of(context).padding.bottom;

  return Container(
    height: availableHeight,
    child: CarouselSlider(
      items: slidesData.map((slideData) {
        return GlassCard(
          gradientColors: slideData.gradientColors,
          child: Padding(
            padding: const EdgeInsets.all(50.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(slideData.icon, size: 80, color: slideData.color),
                SizedBox(height: 30),
                Text(
                  slideData.title,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: slideData.color,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20),
                Text(
                  slideData.description,
                  style: TextStyle(fontSize: 18, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }).toList(),
      options: CarouselOptions(
        height: availableHeight,
        viewportFraction: 1.0,
        enableInfiniteScroll: false,
        autoPlay: true,
        autoPlayInterval: Duration(seconds: 4),
        autoPlayAnimationDuration: Duration(milliseconds: 800),
      ),
    ),
  );
}

// Classe para organizar os dados de cada slide
class SlideData {
  final String title;
  final String description;
  final Color color;
  final IconData icon;
  final List<Color>? gradientColors;

  SlideData({
    required this.title,
    required this.description,
    required this.color,
    required this.icon,
    this.gradientColors,
  });
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

