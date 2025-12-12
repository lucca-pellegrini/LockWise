import 'package:flutter/material.dart';
import 'PaginaBoasVindas.dart';
import 'PaginaInicial.dart';
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
      title: 'LockWise',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],

      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        fontFamily: 'Montserrat',
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontFamily: 'Raleway',
            fontWeight: FontWeight.w600,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Raleway',
            fontWeight: FontWeight.w600,
          ),
          headlineSmall: TextStyle(
            fontFamily: 'Raleway',
            fontWeight: FontWeight.w600,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Raleway',
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            fontFamily: 'Raleway',
            fontWeight: FontWeight.w600,
          ),
          titleSmall: TextStyle(
            fontFamily: 'Raleway',
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(fontFamily: 'Montserrat'),
          bodyMedium: TextStyle(fontFamily: 'Montserrat'),
          bodySmall: TextStyle(fontFamily: 'Montserrat'),
          labelLarge: TextStyle(fontFamily: 'Montserrat'),
          labelMedium: TextStyle(fontFamily: 'Montserrat'),
          labelSmall: TextStyle(fontFamily: 'Montserrat'),
        ),
      ),
      home: FutureBuilder(
        future: AssetPreloader.preloadAssets(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, authSnapshot) {
                if (authSnapshot.connectionState == ConnectionState.active) {
                  final user = authSnapshot.data;
                  if (user != null) {
                    return Inicial(usuarioId: user.uid);
                  } else {
                    return const BoasVindas();
                  }
                } else {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
              },
            );
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
