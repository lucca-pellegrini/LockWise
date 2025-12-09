import 'package:flutter/material.dart';
import 'PaginaBoasVindas.dart';
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'models/AssetPreloader.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Ajusta limites (cuidado para não exagerar)
  PaintingBinding.instance.imageCache.maximumSize = 200; // nº máx de entries
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      150 * 1024 * 1024; // ~150MB

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FechaduraFlow',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],

      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: FutureBuilder(
        future: AssetPreloader.preloadAssets(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return const BoasVindas();
          } else {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
        },
      ),
    );
  }
}
