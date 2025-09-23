import 'package:flutter/material.dart';

class Inicial extends StatefulWidget {
  const Inicial({super.key});

  @override
  State<Inicial> createState() => _InicialState();
}

class _InicialState extends State<Inicial> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: Icon(Icons.menu, size: 40.0, color: Colors.blueAccent),
              onPressed: () {},
            ),
            Text('Tela Inicial', style: TextStyle(color: Colors.blueAccent)),
            IconButton(
              icon: Icon(
                Icons.account_circle,
                size: 40.0,
                color: Colors.blueAccent,
              ),
              onPressed: () {
                // Ação ao pressionar o ícone
                Navigator.pop(context);
              },
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.white10,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Bem-vindo à Página Inicial!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: () {
          setState(() {});
        },
      ),
    );
  }
}
