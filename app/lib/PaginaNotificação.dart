import 'package:flutter/material.dart';
import 'models/LocalService.dart';
import 'dart:ui';
import 'main.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

const String backendUrl = 'http://192.168.0.75:12223';

class Notificacao extends StatefulWidget {
  const Notificacao({super.key});

  @override
  State<Notificacao> createState() => _NotificacaoState();
}

class _NotificacaoState extends State<Notificacao>
    with RouteAware, WidgetsBindingObserver {
  List<Map<String, dynamic>> logs = [];
  bool _isLoading = true;
  Timer? _pollingTimer;
  bool _isAppInForeground = true;
  Map<String, String> deviceNames = {};

  String translateReason(String reason) {
    switch (reason) {
      case 'BUTTON':
        return 'Botão físico';
      case 'TIMEOUT':
        return 'Tempo esgotado';
      case 'MQTT':
        return 'Remoto';
      case 'VOICE':
        return 'Voz';
      case 'REBOOT':
        return 'Reinicialização';
      case 'LOCKDOWN':
        return 'Bloqueio';
      case 'SERIAL':
        return 'Depuração por UART';
      default:
        return reason;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carregarLogs();
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _pollLogs();
    });
  }

  Future<void> _pollLogs() async {
    if (!mounted || !_isAppInForeground) return;
    try {
      final backendToken = await LocalService.getBackendToken();
      if (backendToken == null) return;

      // Get devices from backend
      final devicesResponse = await http.get(
        Uri.parse('$backendUrl/devices'),
        headers: {'Authorization': 'Bearer $backendToken'},
      );
      if (devicesResponse.statusCode != 200) return;
      final devices = jsonDecode(devicesResponse.body) as List;
      final deviceIds = devices.map((d) => d[0] as String).toList();
      if (deviceIds.isEmpty) return;

      // Fetch logs for each device
      List<Map<String, dynamic>> allLogs = [];
      for (final deviceId in deviceIds) {
        final logsResponse = await http.get(
          Uri.parse('$backendUrl/logs/$deviceId'),
          headers: {'Authorization': 'Bearer $backendToken'},
        );
        if (logsResponse.statusCode == 200) {
          final logsData = jsonDecode(logsResponse.body) as List;
          final transformedLogs = logsData.map((log) {
            final timestamp = DateTime.parse(log[2]).millisecondsSinceEpoch;
            final user = log[6] ?? log[5] ?? 'Sistema';
            final action = log[3] == 'LOCK' ? 'Fechar' : 'Abrir';
            final reason = translateReason(log[4]);
            return {
              'data_hora': timestamp,
              'fechadura_nome': deviceNames[deviceId] ?? deviceId,
              'usuario': user,
              'acao': action,
              'reason': reason,
            };
          }).toList();
          allLogs.addAll(transformedLogs);
        }
      }

      // Sort by timestamp descending
      allLogs.sort(
        (a, b) => (b['data_hora'] as int).compareTo(a['data_hora'] as int),
      );

      if (allLogs.length != logs.length ||
          !allLogs.every((log) => logs.contains(log))) {
        setState(() {
          logs = allLogs;
        });
      }
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inscreve no observer da rota para saber quando voltamos para esta tela
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Chamado quando outra rota é fechada e voltamos para esta
  @override
  void didPopNext() {
    _carregarLogs();
  }

  // Chamado quando o app volta para “resumed”
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppInForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _carregarLogs();
    }
  }

  Future<void> _carregarLogs() async {
    try {
      final backendToken = await LocalService.getBackendToken();
      if (backendToken == null) {
        setState(() {
          logs = [];
          _isLoading = false;
        });
        return;
      }

      // Get devices from backend
      final devicesResponse = await http.get(
        Uri.parse('$backendUrl/devices'),
        headers: {'Authorization': 'Bearer $backendToken'},
      );
      if (devicesResponse.statusCode != 200) {
        setState(() {
          logs = [];
          _isLoading = false;
        });
        return;
      }
      final devices = jsonDecode(devicesResponse.body) as List;
      final deviceIds = devices.map((d) => d[0] as String).toList();

      // Fetch device names from Firestore
      final usuario = await LocalService.getUsuarioLogado();
      if (usuario != null) {
        final userId = usuario['id'] as String;
        final querySnapshot = await FirebaseFirestore.instance
            .collection('fechaduras')
            .doc(userId)
            .collection('devices')
            .get();
        final deviceDocs = querySnapshot.docs;
        deviceNames = {
          for (var doc in deviceDocs) doc.id: doc.data()['nome'] as String,
        };
      }

      // Fetch logs for each device
      List<Map<String, dynamic>> allLogs = [];
      for (final deviceId in deviceIds) {
        final logsResponse = await http.get(
          Uri.parse('$backendUrl/logs/$deviceId'),
          headers: {'Authorization': 'Bearer $backendToken'},
        );
        if (logsResponse.statusCode == 200) {
          final logsData = jsonDecode(logsResponse.body) as List;
          final transformedLogs = logsData.map((log) {
            final timestamp = DateTime.parse(log[2]).millisecondsSinceEpoch;
            final user = log[6] ?? log[5] ?? 'Sistema';
            final action = log[3] == 'LOCK' ? 'Fechar' : 'Abrir';
            final reason = translateReason(log[4]);
            return {
              'data_hora': timestamp,
              'fechadura_nome': deviceNames[deviceId] ?? deviceId,
              'usuario': user,
              'acao': action,
              'reason': reason,
            };
          }).toList();
          allLogs.addAll(transformedLogs);
        }
      }

      // Sort by timestamp descending
      allLogs.sort(
        (a, b) => (b['data_hora'] as int).compareTo(a['data_hora'] as int),
      );

      setState(() {
        logs = allLogs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        logs = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,

      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: DataTableTheme(
                      data: DataTableThemeData(
                        dataRowMinHeight: 32,
                        dataRowMaxHeight: 40,
                        headingRowHeight: 40,
                        columnSpacing: 25,
                        horizontalMargin: 10,
                        dividerThickness: 1.5,
                      ),

                      child: Theme(
                        data: Theme.of(context).copyWith(
                          visualDensity: const VisualDensity(
                            vertical: -3,
                            horizontal: -1,
                          ),
                        ),

                        child: DataTable(
                          columns: const [
                            DataColumn(
                              label: Text(
                                'Horário',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Fechadura',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Conta',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Ação',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Motivo',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],

                          rows: logs.isEmpty
                              ? [
                                  DataRow(
                                    cells: const [
                                      DataCell(
                                        Text(
                                          'Nenhum log',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          'Nenhum log',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          'Nenhum log',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          'Nenhum log',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          'Nenhum log',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ]
                              : logs.map((log) {
                                  final dataHora =
                                      DateTime.fromMillisecondsSinceEpoch(
                                        log['data_hora'] as int,
                                      );
                                  final horario =
                                      '${dataHora.day.toString().padLeft(2, '0')}/${dataHora.month.toString().padLeft(2, '0')} '
                                      '${dataHora.hour.toString().padLeft(2, '0')}:${dataHora.minute.toString().padLeft(2, '0')}';

                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        Text(
                                          horario,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          log['fechadura_nome'] ?? 'N/A',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          log['usuario'] ?? 'N/A',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          log['acao'] ?? 'N/A',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          log['reason'] ?? 'N/A',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
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
                      Colors.blueAccent.withOpacity(0.3),
                      Colors.blueAccent.withOpacity(0.1),
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
