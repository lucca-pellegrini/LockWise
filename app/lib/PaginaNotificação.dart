import 'package:flutter/material.dart';
import 'dart:ui';
import 'models/database.dart';
import 'models/LocalService.dart';
import 'main.dart';

class Notificacao extends StatefulWidget {
  const Notificacao({super.key});

  @override
  State<Notificacao> createState() => _NotificacaoState();
}

class _NotificacaoState extends State<Notificacao>
    with RouteAware, WidgetsBindingObserver {
  List<Map<String, dynamic>> logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carregarLogs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inscreve no observer da rota para saber quando voltamos para esta tela
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
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
    if (state == AppLifecycleState.resumed) {
      _carregarLogs();
    }
  }

  Future<void> _carregarLogs() async {
    try {
      final user = await LocalService.getUsuarioLogado();
      if (user == null) {
        setState(() {
          logs = [];
          _isLoading = false;
        });
        return;
      }
      final usuarioId = user['id'] as int;
      // Busca logs de todas as fechaduras do usuário, já com fechadura_nome
      final result = await DB.instance.listarLogsDoUsuario(usuarioId);
      setState(() {
        logs = result;
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

