import 'package:flutter/material.dart';
import 'models/LocalService.dart';
import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'PaginaDetalhe.dart' hide backendUrl;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

const String backendUrl = 'http://192.168.0.75:12223';

class Temporaria extends StatefulWidget {
  const Temporaria({super.key});

  @override
  State<Temporaria> createState() => _TemporariaState();
}

class _TemporariaState extends State<Temporaria> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _fechadurasTemporarias = [];
  bool _isLoading = true;
  Map<String, dynamic>? _usuario;
  Timer? _pollTimer;
  Timer? _statusPollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carregarFechadurasTemporarias();
    _pollTimer = Timer.periodic(Duration(seconds: 30), (_) => _pollDevices());
    _startStatusPolling();
  }

  void _startStatusPolling() {
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _pollStatuses();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _statusPollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollDevices() async {
    try {
      _usuario = await LocalService.getUsuarioLogado();

      if (_usuario != null) {
        final backendToken = await LocalService.getBackendToken();
        if (backendToken != null) {
          final response = await http.get(
            Uri.parse('$backendUrl/accessible_devices'),
            headers: {'Authorization': 'Bearer $backendToken'},
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as List;
            final fechadurasComAcesso = <Map<String, dynamic>>[];

            for (final device in data) {
              final deviceId = device['device_id'];
              final senderId = device['sender_id'];
              final expiryTimestamp = device['expiry_timestamp'];

              final dataExpiracao = DateTime.fromMillisecondsSinceEpoch(
                expiryTimestamp,
              );
              final agora = DateTime.now();

              if (agora.isBefore(dataExpiracao) ||
                  expiryTimestamp >
                      DateTime.now()
                          .add(Duration(days: 30000))
                          .millisecondsSinceEpoch) {
                // Buscar dados da fechadura
                final fechaduraDoc = await FirebaseFirestore.instance
                    .collection('fechaduras')
                    .doc(senderId)
                    .collection('devices')
                    .doc(deviceId)
                    .get();
                final fechadura = fechaduraDoc.exists
                    ? fechaduraDoc.data()
                    : null;

                if (fechadura != null) {
                  // Buscar dados do proprietário
                  final proprietarioDoc = await FirebaseFirestore.instance
                      .collection('usuarios')
                      .doc(senderId)
                      .get();
                  final proprietario = proprietarioDoc.exists
                      ? proprietarioDoc.data()
                      : null;

                  fechadurasComAcesso.add({
                    'fechadura': fechadura,
                    'device': device,
                    'proprietario': proprietario,
                    'data_expiracao': dataExpiracao,
                  });
                }
              }
            }

            // Compare device IDs
            final currentIds = _fechadurasTemporarias
                .map((e) => e['device']['device_id'])
                .toSet();
            final newIds = fechadurasComAcesso
                .map((e) => e['device']['device_id'])
                .toSet();

            if (currentIds != newIds) {
              setState(() {
                _fechadurasTemporarias = fechadurasComAcesso;
              });
              // Since list changed, poll statuses to update
              await _pollStatuses();
            }
          }
        }
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _pollStatuses() async {
    if (_fechadurasTemporarias.isEmpty) return;
    final backendToken = await LocalService.getBackendToken();
    if (backendToken == null) return;
    try {
      final response = await http.get(
        Uri.parse('$backendUrl/temp_devices_status'),
        headers: {'Authorization': 'Bearer $backendToken'},
      );
      if (response.statusCode == 200) {
        final devices = jsonDecode(response.body) as List;
        setState(() {
          for (var item in _fechadurasTemporarias) {
            final deviceId = item['device']['device_id'];
            final device = devices.firstWhere(
              (d) => d['uuid'] == deviceId,
              orElse: () => null,
            );
            if (device != null) {
              final lastHeard = device['last_heard'];
              final isOnline =
                  lastHeard != null &&
                  (DateTime.now().millisecondsSinceEpoch - lastHeard) < 15000;
              final isUnlocked = device['lock_state'] == 'UNLOCKED';
              final lockedDownAt = device['locked_down_at'];
              item['isOnline'] = isOnline;
              item['isUnlocked'] = isUnlocked;
              item['locked_down_at'] = lockedDownAt;
            } else {
              item['isOnline'] = false;
              item['isUnlocked'] = false;
              item['locked_down_at'] = null;
            }
          }
        });
      }
    } catch (e) {
      // ignore
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Recarrega quando o app volta ao foco
      _carregarFechadurasTemporarias();
    }
  }

  // Adicione este método para recarregar manualmente
  Future<void> _recarregarDados() async {
    await _carregarFechadurasTemporarias();
  }

  Future<void> _carregarFechadurasTemporarias() async {
    setState(() => _isLoading = true);

    try {
      _usuario = await LocalService.getUsuarioLogado();

      if (_usuario != null) {
        final backendToken = await LocalService.getBackendToken();
        if (backendToken != null) {
          final response = await http.get(
            Uri.parse('$backendUrl/accessible_devices'),
            headers: {'Authorization': 'Bearer $backendToken'},
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as List;
            final fechadurasComAcesso = <Map<String, dynamic>>[];

            for (final device in data) {
              final deviceId = device['device_id'];
              final senderId = device['sender_id'];
              final expiryTimestamp = device['expiry_timestamp'];

              final dataExpiracao = DateTime.fromMillisecondsSinceEpoch(
                expiryTimestamp,
              );
              final agora = DateTime.now();

              if (agora.isBefore(dataExpiracao) ||
                  expiryTimestamp >
                      DateTime.now()
                          .add(Duration(days: 30000))
                          .millisecondsSinceEpoch) {
                // Buscar dados da fechadura
                final fechaduraDoc = await FirebaseFirestore.instance
                    .collection('fechaduras')
                    .doc(senderId)
                    .collection('devices')
                    .doc(deviceId)
                    .get();
                final fechadura = fechaduraDoc.exists
                    ? fechaduraDoc.data()
                    : null;

                if (fechadura != null) {
                  // Buscar dados do proprietário
                  final proprietarioDoc = await FirebaseFirestore.instance
                      .collection('usuarios')
                      .doc(senderId)
                      .get();
                  final proprietario = proprietarioDoc.exists
                      ? proprietarioDoc.data()
                      : null;

                  fechadurasComAcesso.add({
                    'fechadura': fechadura,
                    'device': device,
                    'proprietario': proprietario,
                    'data_expiracao': dataExpiracao,
                  });
                }
              }
            }

            setState(() {
              _fechadurasTemporarias = fechadurasComAcesso;
              _isLoading = false;
            });
            await _pollStatuses();
          } else {
            setState(() => _isLoading = false);
          }
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      print('Erro ao carregar fechaduras temporárias: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _recarregarDados, // Permite pull-to-refresh
      color: Colors.blueAccent,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: Colors.blueAccent))
            : _fechadurasTemporarias.isEmpty
            ? () {
                print('DEBUG: No temporary locks to display');
                return _buildEmptyState();
              }()
            : _buildFechadurasList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: EdgeInsets.all(40),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blueAccent.withOpacity(0.2),
                  Colors.blueAccent.withOpacity(0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.access_time, size: 64, color: Colors.white54),
                SizedBox(height: 16),
                Text(
                  'Nenhum acesso temporário',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Você não possui acesso temporário a nenhuma fechadura no momento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFechadurasList() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12.0,
        crossAxisSpacing: 12.0,
        childAspectRatio: 1.0,
      ),
      itemCount: _fechadurasTemporarias.length,
      itemBuilder: (context, index) {
        final item = _fechadurasTemporarias[index];
        return _buildFechaduraCard(item);
      },
    );
  }

  Widget _buildFechaduraCard(Map<String, dynamic> item) {
    final fechadura = item['fechadura'] as Map<String, dynamic>;
    final device = item['device'] as Map<String, dynamic>;
    final proprietario = item['proprietario'] as Map<String, dynamic>?;
    final dataExpiracao = item['data_expiracao'] as DateTime;

    final agora = DateTime.now();
    final diasRestantes = dataExpiracao.difference(agora).inDays;
    final horasRestantes = dataExpiracao.difference(agora).inHours;
    final isPermanente = diasRestantes > 30000;

    final isOnline = item['isOnline'] ?? false;
    final isUnlocked = item['isUnlocked'] ?? false;

    Border myBorder;
    List<BoxShadow>? myShadow;
    LinearGradient myGradient;
    if (item['locked_down_at'] != null) {
      myGradient = LinearGradient(
        colors: [Colors.red.withOpacity(0.3), Colors.red.withOpacity(0.1)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      myBorder = Border.all(color: Colors.red, width: 3);
      myShadow = null;
    } else {
      myGradient = LinearGradient(
        colors: [
          Colors.blueAccent.withOpacity(0.3),
          Colors.blueAccent.withOpacity(0.1),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      myShadow = null;
      if (!isOnline) {
        myBorder = Border.all(color: Colors.orange.shade800, width: 3);
      } else if (isUnlocked) {
        myBorder = Border.all(color: Colors.green, width: 3);
      } else {
        myBorder = Border.all(color: Colors.white.withOpacity(0.5), width: 1);
      }
    }

    return Card.outlined(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              gradient: myGradient,
              borderRadius: BorderRadius.circular(20),
              border: myBorder,
              boxShadow: myShadow,
            ),
            child: InkWell(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => _TemporaryDeviceDialog(
                    deviceId: device['device_id'],
                    deviceName: fechadura?['nome'] ?? 'Fechadura',
                    deviceIcon: _getIconeFechadura(fechadura),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ícone e nome da fechadura
                    Row(
                      children: [
                        Icon(
                          IconData(
                            fechadura['icone_code_point'] ??
                                Icons.lock.codePoint,
                            fontFamily: 'MaterialIcons',
                          ),
                          size: 32,
                          color: Colors.white,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            fechadura['nome'] ?? 'Fechadura',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 16),

                    // Proprietário
                    Row(
                      children: [
                        Icon(Icons.person, size: 16, color: Colors.white70),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            proprietario?['nome'] ?? 'Proprietário',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    Spacer(),

                    // Badge de bloqueio if locked down
                    if (item['locked_down_at'] != null) ...[
                      Center(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.security, size: 12, color: Colors.red),
                              SizedBox(width: 4),
                              Text(
                                'Bloqueada',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                    ] else if (isOnline && isUnlocked) ...[
                      Center(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock_open,
                                size: 12,
                                color: Colors.green,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Aberta',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                    ] else if (!isOnline) ...[
                      Center(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade800.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.shade800.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.wifi_off,
                                size: 12,
                                color: Colors.orange.shade800,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Desconectada',
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                    ],

                    // Badge de acesso temporário
                    Center(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(
                            diasRestantes,
                            isPermanente,
                          ).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _getStatusColor(
                              diasRestantes,
                              isPermanente,
                            ).withOpacity(0.5),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPermanente
                                  ? Icons.all_inclusive
                                  : Icons.access_time,
                              size: 12,
                              color: _getStatusColor(
                                diasRestantes,
                                isPermanente,
                              ),
                            ),
                            SizedBox(width: 4),
                            Text(
                              _getStatusText(
                                diasRestantes,
                                horasRestantes,
                                isPermanente,
                              ),
                              style: TextStyle(
                                color: _getStatusColor(
                                  diasRestantes,
                                  isPermanente,
                                ),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(int diasRestantes, bool isPermanente) {
    if (isPermanente) return Colors.green;
    if (diasRestantes <= 1) return Colors.red;
    if (diasRestantes <= 7) return Colors.orange;
    return Colors.blue;
  }

  String _getStatusText(
    int diasRestantes,
    int horasRestantes,
    bool isPermanente,
  ) {
    if (isPermanente) return 'Acesso Permanente';

    if (diasRestantes <= 0) {
      if (horasRestantes <= 0) {
        return 'Expirado';
      } else {
        return 'Expira em ${horasRestantes}h';
      }
    } else if (diasRestantes == 1) {
      return 'Expira amanhã';
    } else if (diasRestantes <= 7) {
      return 'Expira em $diasRestantes dias';
    } else if (diasRestantes <= 30) {
      return 'Expira em $diasRestantes dias';
    } else {
      final semanas = (diasRestantes / 7).round();
      return 'Expira em $semanas semanas';
    }
  }

  void _mostrarSucesso(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  IconData _getIconeFechadura(Map<String, dynamic>? fechadura) {
    if (fechadura == null) return Icons.lock;

    final codePoint = fechadura['icone_code_point'];
    if (codePoint == null || codePoint == 0) return Icons.lock;

    return IconData(codePoint, fontFamily: 'MaterialIcons');
  }
}

class _GlassButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isEnabled;
  final Color color;
  final double width;
  final double height;
  final double fontSize;

  const _GlassButton({
    required this.text,
    required this.onPressed,
    this.isEnabled = true,
    this.color = Colors.blueAccent,
    this.width = 100,
    this.height = 40,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
          ),
          child: InkWell(
            onTap: isEnabled
                ? onPressed
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'A fechadura não pode ser alcançada no momento. Pode se tratar de um problema de conexão ou de um lockdown de emergência.',
                          style: TextStyle(color: Colors.black),
                        ),
                        backgroundColor: Colors.orange.shade300,
                        duration: Duration(seconds: 5),
                      ),
                    );
                  },
            child: Center(
              child: Text(
                text,
                style: TextStyle(
                  color: isEnabled ? Colors.white : Colors.grey[400],
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TemporaryDeviceDialog extends StatefulWidget {
  final String deviceId;
  final String deviceName;
  final IconData deviceIcon;

  const _TemporaryDeviceDialog({
    required this.deviceId,
    required this.deviceName,
    required this.deviceIcon,
  });

  @override
  State<_TemporaryDeviceDialog> createState() => _TemporaryDeviceDialogState();
}

class _TemporaryDeviceDialogState extends State<_TemporaryDeviceDialog>
    with WidgetsBindingObserver {
  bool isOpen = true;
  int? lastHeard;
  int? pingMs;
  Timer? _pollingTimer;
  bool _isAppInForeground = true;
  bool isLockedDown = false;

  bool get isConnected =>
      lastHeard != null &&
      (DateTime.now().millisecondsSinceEpoch - lastHeard!) < 15000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carregarDados();
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _pollUpdates();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppInForeground = state == AppLifecycleState.resumed;
  }

  Future<void> _pollUpdates() async {
    if (!mounted || !_isAppInForeground) return;
    final backendToken = await LocalService.getBackendToken();
    if (backendToken == null) return;

    // Poll device state
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final deviceResponse = await http.get(
          Uri.parse('$backendUrl/temp_device/${widget.deviceId}'),
          headers: {'Authorization': 'Bearer $backendToken'},
        );
        if (deviceResponse.statusCode == 200) {
          final deviceData = jsonDecode(deviceResponse.body);
          final newIsOpen = deviceData['lock_state'] == 'UNLOCKED';
          final newLastHeard = deviceData['last_heard'];
          final newIsLockedDown = deviceData['locked_down_at'] != null;
          if (newIsOpen != isOpen ||
              newLastHeard != lastHeard ||
              newIsLockedDown != isLockedDown) {
            setState(() {
              isOpen = newIsOpen;
              lastHeard = newLastHeard;
              isLockedDown = newIsLockedDown;
            });
          }
        }
        break;
      } catch (e) {
        if (attempt == 1) {
          // Ignore after 2 attempts
        } else {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    // Poll ping if connected
    if (isConnected) {
      final start = DateTime.now().millisecondsSinceEpoch;
      final pingResponse = await http.post(
        Uri.parse('$backendUrl/temp_ping/${widget.deviceId}'),
        headers: {'Authorization': 'Bearer $backendToken'},
      );
      if (pingResponse.statusCode == 200) {
        final end = DateTime.now().millisecondsSinceEpoch;
        final newPingMs = ((end - start) / 2).round();
        if (newPingMs != pingMs) {
          setState(() {
            pingMs = newPingMs;
          });
        }
      }
    }
  }

  Future<void> _carregarDados() async {
    try {
      final backendToken = await LocalService.getBackendToken();
      if (backendToken != null) {
        final deviceResponse = await http.get(
          Uri.parse('$backendUrl/temp_device/${widget.deviceId}'),
          headers: {'Authorization': 'Bearer $backendToken'},
        );
        if (deviceResponse.statusCode == 200) {
          final deviceData = jsonDecode(deviceResponse.body);
          isOpen = deviceData['lock_state'] == 'UNLOCKED';
          lastHeard = deviceData['last_heard'];
          isLockedDown = deviceData['locked_down_at'] != null;
        }
      }
      setState(() {});
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _registrarAcao(String acao) async {
    try {
      final usuario = await LocalService.getUsuarioLogado();
      final userId = usuario?['id'] as String;
      final backendToken = await LocalService.getBackendToken();

      if (backendToken == null) {
        throw Exception('No backend token');
      }

      final command = acao == 'Abrir' ? 'UNLOCK' : 'LOCK';
      final url = '$backendUrl/temp_control/${widget.deviceId}';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $backendToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'command': command, 'user_id': userId}),
      );

      if (response.statusCode != 200) {
        throw Exception('Backend error: ${response.statusCode}');
      }

      // Pause polling for 5 seconds to allow backend to update database
      _pollingTimer?.cancel();
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          _startPolling();
        }
      });

      // Also pause the main status polling timer if it exists
      final temporariaState = context
          .findAncestorStateOfType<_TemporariaState>();
      temporariaState?._statusPollingTimer?.cancel();
      Future.delayed(const Duration(seconds: 5), () {
        if (temporariaState != null && temporariaState.mounted) {
          temporariaState._startStatusPolling();
        }
      });

      setState(() {
        isOpen = acao == 'Abrir';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fechadura ${acao == 'Abrir' ? 'abriu' : 'fechou'} com sucesso!',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao $acao fechadura: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blueAccent.withOpacity(0.3),
                  Colors.blueAccent.withOpacity(0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBar(
                  title: Text(
                    'Detalhes da Fechadura',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  iconTheme: IconThemeData(color: Colors.white),
                  actions: [
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            widget.deviceIcon,
                            size: 50,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.deviceName,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      isLockedDown
                                          ? Icons.security
                                          : (isOpen
                                                ? Icons.lock_open
                                                : Icons.lock),
                                      color: isLockedDown
                                          ? Colors.red
                                          : (isOpen
                                                ? Colors.orange.shade800
                                                : Colors.green),
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      isLockedDown
                                          ? 'Bloqueada'
                                          : (isOpen ? 'Aberta' : 'Fechada'),
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                if (!isLockedDown)
                                  Row(
                                    children: [
                                      Icon(
                                        isConnected
                                            ? Icons.wifi
                                            : Icons.wifi_off,
                                        color: isConnected
                                            ? Colors.green
                                            : Colors.orange.shade800,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        isConnected
                                            ? 'Conectada'
                                            : 'Desconectada',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                if (!isLockedDown && isConnected)
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.speed,
                                        color: pingMs == null
                                            ? Colors.white
                                            : pingMs! > 1000
                                            ? Colors.orange.shade800
                                            : pingMs! < 500
                                            ? Colors.green
                                            : Colors.yellow.shade700,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Ping: ${pingMs ?? '?'}ms',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _GlassButton(
                            onPressed: isConnected && !isLockedDown
                                ? () {
                                    final acao = isOpen ? 'Fechar' : 'Abrir';
                                    _registrarAcao(acao);
                                  }
                                : null,
                            text: (isOpen ? 'Fechar' : 'Abrir'),
                            isEnabled: isConnected && !isLockedDown,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
