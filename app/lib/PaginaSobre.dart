import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';

class Sobre extends StatelessWidget {
  const Sobre({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFfdfdfd),
      appBar: AppBar(
        title: Text('Sobre', style: TextStyle(color: Colors.blueAccent)),
        centerTitle: true,
        backgroundColor: Color(0xFFfdfdfd),

        iconTheme: IconThemeData(color: Colors.blueAccent, size: 30.0),
      ),

      body: content(context), // Passando context para calcular altura
    );
  }
}

Widget content(BuildContext context) {
  // Lista com conteúdo específico para cada slide
  final List<SlideData> slidesData = [
    SlideData(
      title: "O que é o LockWise?",
      description:
          "O LockWise controla suas fechaduras de forma inteligentes segura e prática",
      color: Colors.blue,
      icon: Icons.home_outlined,
    ),
    SlideData(
      title: "Controle por Senha",
      description: "Acesse sua casa usando senha numérica personalizada",
      color: Colors.green,
      icon: Icons.lock_outline,
    ),
    SlideData(
      title: "Comando de Voz",
      description: "Abra e feche as portas usando comandos de voz inteligentes",
      color: Colors.orange,
      icon: Icons.mic,
    ),
    SlideData(
      title: "Tecnologia NFC",
      description:
          "Use cartões ou dispositivos NFC para acesso rápido e seguro",
      color: Colors.purple,
      icon: Icons.nfc_outlined,
    ),
    SlideData(
      title: "Monitoramento 24/7",
      description:
          "Receba notificações em tempo real sobre acessos e status das fechaduras",
      color: Colors.red,
      icon: Icons.notifications_outlined,
    ),
    SlideData(
      title: "Responsáveis pelo App",
      description:
          "Amanda Canizela, Ariel Inácio, Lucas Alvarenga, Lucca Pellegrini",
      color: Colors.blueGrey,
      icon: Icons.code_outlined,
    ),
    SlideData(
      title: "Responsáveis pela Fechadura",
      description: "Felipe de Mello, Lucca Pellegrini",
      color: Colors.pinkAccent,
      icon: Icons.build_outlined,
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
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: slideData.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: slideData.color, width: 3),
          ),
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
                  style: TextStyle(fontSize: 18, color: Colors.grey[700]),
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

  SlideData({
    required this.title,
    required this.description,
    required this.color,
    required this.icon,
  });
}

