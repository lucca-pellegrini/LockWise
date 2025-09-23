import 'package:flutter/material.dart';

class LockDetails extends StatelessWidget {
  const LockDetails({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Detalhes da Fechadura',
          style: TextStyle(color: Colors.blueAccent),
        ),
        centerTitle: true,
        backgroundColor: Colors.white10,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image placeholder and description
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Placeholder image
                Container(
                  width: 100,
                  height: 100,
                  color: Colors.grey[300],
                  child: Icon(Icons.lock, size: 50, color: Colors.grey),
                ),
                const SizedBox(width: 16),
                // Description with status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fechadura Principal',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Status: Fechada'),
                      Text('Conectada: Sim'),
                      Text('Último acesso: 10:30 AM'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(onPressed: () {}, child: Text('Abrir')),
                ElevatedButton(onPressed: () {}, child: Text('Fechar')),
              ],
            ),
            const SizedBox(height: 20),
            // Toggles for configuration
            Text(
              'Configurações:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              title: Text('Notificações'),
              value: true,
              onChanged: (bool value) {},
            ),
            SwitchListTile(
              title: Text('Acesso remoto'),
              value: false,
              onChanged: (bool value) {},
            ),
            const SizedBox(height: 20),
            // Access log table
            Text(
              'Log de Acessos:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            DataTable(
              columns: const [
                DataColumn(label: Text('Horário')),
                DataColumn(label: Text('Conta')),
                DataColumn(label: Text('Método')),
              ],
              rows: const [
                DataRow(
                  cells: [
                    DataCell(Text('10:30 AM')),
                    DataCell(Text('João Silva')),
                    DataCell(Text('PIN')),
                  ],
                ),
                DataRow(
                  cells: [
                    DataCell(Text('09:15 AM')),
                    DataCell(Text('Maria Santos')),
                    DataCell(Text('Voz')),
                  ],
                ),
                DataRow(
                  cells: [
                    DataCell(Text('08:45 AM')),
                    DataCell(Text('Cauã Armani')),
                    DataCell(Text('Arrombou a porta')),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

