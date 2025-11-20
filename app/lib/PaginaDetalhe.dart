import 'package:flutter/material.dart';
import 'database.dart';
import 'LocalService.dart';

class LockDetails extends StatefulWidget {
  final int fechaduraId;

  LockDetails({super.key, required this.fechaduraId});

  @override
  State<LockDetails> createState() => _LockDetailsState();
}

class _LockDetailsState extends State<LockDetails> {
  bool notificationsEnabled = true;
  bool remoteAccessEnabled = false;
  Map<String, dynamic>? fechadura;
  bool _isLoading = true;
  List<Map<String, dynamic>> logs = [];

  @override
  void initState() {
    super.initState();
    _carregarDadosFechadura();
  }

  Future<void> _carregarDadosFechadura() async {
    try {
      final f = await DB.instance.buscarFechadura(widget.fechaduraId);
      final logsData = await DB.instance.listarLogsDeAcesso(widget.fechaduraId);
      setState(() {
        fechadura = f;
        logs = logsData;
        notificationsEnabled = f?['notificacoes'] == 1;
        remoteAccessEnabled = f?['acesso_remoto'] == 1;
        _isLoading = false;
      });
    } catch (e) {
      print('Erro ao carregar fechadura: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Color(0xFFfdfdfd),
      appBar: AppBar(
        title: Text(
          'Detalhes da Fechadura',
          style: TextStyle(color: Colors.blueAccent),
        ),

        iconTheme: IconThemeData(color: Colors.blueAccent, size: 30.0),

        centerTitle: true,
        backgroundColor: Color(0xFFfdfdfd),
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
                        fechadura?['nome'] ?? 'Fechadura',
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
              value: notificationsEnabled,
              onChanged: (bool value) async {
                setState(() {
                  notificationsEnabled = value;
                });

                await DB.instance.atualizarFechadura(widget.fechaduraId, {
                  'notificacoes': value ? 1 : 0,
                });
              },
            ),
            SwitchListTile(
              title: Text('Acesso remoto'),
              value: remoteAccessEnabled,
              onChanged: (bool value) async {
                setState(() {
                  remoteAccessEnabled = value;
                });

                await DB.instance.atualizarFechadura(widget.fechaduraId, {
                  'acesso_remoto': value ? 1 : 0,
                });
              },
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
                DataColumn(label: Text('Ação')),
                DataColumn(label: Text('Método')),
              ],
              rows: logs.isEmpty
                  ? [
                      DataRow(
                        cells: [
                          DataCell(Text('Nenhum log')),
                          DataCell(Text('Nenhum log')),
                          DataCell(Text('Nenhum log')),
                          DataCell(Text('Nenhum log')),
                        ],
                      ),
                    ]
                  : logs.map((log) {
                      final dataHora = DateTime.fromMillisecondsSinceEpoch(
                        log['data_hora'] as int,
                      );
                      final horario =
                          '${dataHora.hour.toString().padLeft(2, '0')}:${dataHora.minute.toString().padLeft(2, '0')}';

                      return DataRow(
                        cells: [
                          DataCell(Text(horario)),
                          DataCell(Text(log['usuario'] ?? 'N/A')),
                          DataCell(Text(log['acao'] ?? 'N/A')),
                          DataCell(Text(log['tipo_acesso'] ?? 'N/A')),
                        ],
                      );
                    }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
