import 'package:flutter/widgets.dart';

class AssetPreloader {
  static final List<ImageProvider> persistentAssets = [
    const AssetImage('images/Fundo.jpg'),
    const AssetImage('images/Logo.png'),
    const AssetImage('images/BemVindo.png'),
    const AssetImage('images/SemChave.png'),
    const AssetImage('images/Desbloqueie.png'),
    const AssetImage('images/Compartilhe.png'),
    const AssetImage('images/Notificacao.png'),
    const AssetImage('images/Fundo8.jpg'),
  ];

  static bool _started = false;
  static Future<void> preloadAll(BuildContext context) async {
    if (_started) return;
    _started = true;
    await Future.wait(persistentAssets.map((a) => precacheImage(a, context)));
  }

  static Future<void> preloadAssets() async {
    await Future.delayed(Duration.zero);
  }
}

