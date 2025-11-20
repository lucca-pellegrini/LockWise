import 'package:flutter/material.dart';

class Notificacao extends StatefulWidget {
  const Notificacao({super.key});

  @override
  State<Notificacao> createState() => _NotificacaoState();
}

class _NotificacaoState extends State<Notificacao> {
  List<Map<String, dynamic>> logs = [];
  bool _isLoading = true;

  @override
  Widget build(BuildContext context) {
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

      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notificações:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Horário')),
                    DataColumn(label: Text('Fechadura')),
                    DataColumn(label: Text('Conta')),
                    DataColumn(label: Text('Ação')),
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
                              '${dataHora.day.toString().padLeft(2, '0')}/${dataHora.month.toString().padLeft(2, '0')} '
                              '${dataHora.hour.toString().padLeft(2, '0')}:${dataHora.minute.toString().padLeft(2, '0')}';

                          return DataRow(
                            cells: [
                              DataCell(Text(horario)),
                              DataCell(Text(log['fechadura_nome'] ?? 'N/A')),
                              DataCell(Text(log['usuario'] ?? 'N/A')),
                              DataCell(Text(log['acao'] ?? 'N/A')),
                            ],
                          );
                        }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
