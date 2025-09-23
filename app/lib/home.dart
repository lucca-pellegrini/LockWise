import 'package:flutter/material.dart';
import 'lock_details.dart';

class Inicial extends StatefulWidget {
  const Inicial({super.key});

  @override
  State<Inicial> createState() => _InicialState();
}

class _InicialState extends State<Inicial> {
  // Placeholder data for locks
  final List<Map<String, String>> locks = [
    {'name': 'Fechadura 1', 'status': 'Fechada'},
    {'name': 'Fechadura 2', 'status': 'Aberta'},
    {'name': 'Fechadura 3', 'status': 'Fechada'},
  ];

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
            Text('LockWise', style: TextStyle(color: Colors.blueAccent)),
            IconButton(
              icon: Icon(
                Icons.account_circle,
                size: 40.0,
                color: Colors.blueAccent,
              ),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.white10,
        automaticallyImplyLeading: false,
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return GridView.builder(
            padding: const EdgeInsets.all(16.0),
            gridDelegate: orientation == Orientation.portrait
                ? const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16.0,
                    mainAxisSpacing: 16.0,
                    childAspectRatio: 1.0,
                  )
                : const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200.0,
                    crossAxisSpacing: 16.0,
                    mainAxisSpacing: 16.0,
                    childAspectRatio: 1.0,
                  ),
            itemCount: locks.length,
            itemBuilder: (context, index) {
              final lock = locks[index];
              return Card(
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const LockDetails()),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock, size: 48, color: Colors.blueAccent),
                        const SizedBox(height: 8),
                        Text(
                          lock['name']!,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Status: ${lock['status']}',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: () {},
      ),
    );
  }
}
