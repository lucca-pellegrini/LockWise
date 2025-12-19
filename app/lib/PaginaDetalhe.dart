import 'package:flutter/material.dart';
import 'LocalService.dart';
import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'PaginaDetalhe.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

class LockDetails extends StatefulWidget {
  final String fechaduraId;

  LockDetails({super.key, required this.fechaduraId});

  @override
  State<LockDetails> createState() => _LockDetailsState();
}

class _LockDetailsState extends State<LockDetails> with WidgetsBindingObserver {
  bool notificationsEnabled = true;
  bool administrador = true;
  bool isOpen = true;
  bool _isLoading = true;
  Map<String, dynamic>? fechadura;
  List<Map<String, dynamic>> logs = [];
  int? lastHeard;
  int? pingMs;
  String _duracaoSelecionada = '1_semana';

  // Config controllers
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _wifiSsidController = TextEditingController();
  final TextEditingController _wifiPasswordController = TextEditingController();
  final TextEditingController _audioTimeoutController = TextEditingController();
  final TextEditingController _lockTimeoutController = TextEditingController();
  final TextEditingController _pairingTimeoutController =
      TextEditingController();

  // Initial config values for comparison
  String _initialWifiSsid = '';
  String _initialAudioTimeout = '';
  String _initialLockTimeout = '';
  String _initialPairingTimeout = '';
  bool _initialVoiceDetectionEnabled = true;
  bool _initialVoiceInviteEnabled = true;
  double _initialVoiceThreshold = 0.60;
  int _initialVadRmsThreshold = 1000;
  bool _voiceDetectionEnabled = true;
  bool _voiceInviteEnabled = true;
  double _voiceThreshold = 0.60;
  int _vadRmsThreshold = 1000;

  bool get isConnected =>
      lastHeard != null &&
      (DateTime.now().millisecondsSinceEpoch - lastHeard!) < 30000;
  final _conviteFormKey = GlobalKey<FormState>();
  final _configFormKey = GlobalKey<FormState>();
  final _idUsuarioController = TextEditingController();
  WebSocketChannel? _webSocketChannel;
  bool _isAppInForeground = true;

  String translateReason(String reason) {
    switch (reason) {
      case 'BUTTON':
        return 'Botão físico';
      case 'TIMEOUT':
        return 'Tempo esgotado';
      case 'MQTT':
        return 'Aplicativo';
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

  String getUserDisplay(String? userName, String? userId, String reason) {
    if (userName != null || userId != null) {
      return userName ?? userId!;
    } else if (reason == 'MQTT') {
      return 'Desconhecido';
    } else {
      return 'Sistema';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carregarDadosFechadura();
    _connectWebSocket();
  }

  bool get isLockedDown => fechadura?['locked_down_at'] != null;

  void _connectWebSocket() async {
    final backendToken = await LocalService.getBackendToken();
    if (backendToken == null) return;

    final backendUri = Uri.parse(LocalService.backendUrl);
    final uri = Uri(
      scheme: backendUri.scheme == 'https' ? 'wss' : 'ws',
      host: backendUri.host,
      port: backendUri.port,
      path: '/ws/updates',
      queryParameters: {'token': backendToken},
    );
    _webSocketChannel = WebSocketChannel.connect(uri);

    // Listen for messages
    _webSocketChannel!.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message);
          if (data['type'] == 'device_online' &&
              data['device_id'] == widget.fechaduraId) {
            final lastHeard = data['last_heard'];
            final lockState = data['lock_state'];
            setState(() {
              lastHeard != null ? lastHeard : this.lastHeard;
              isOpen = lockState == 'UNLOCKED';
            });
          } else if (data['type'] == 'device_update' &&
              data['device_id'] == widget.fechaduraId) {
            final lockState = data['lock_state'];
            setState(() {
              isOpen = lockState == 'UNLOCKED';
            });
          } else if (data['type'] == 'log_update' &&
              data['device_id'] == widget.fechaduraId) {
            // Add new log to list
            final timestamp = data['timestamp'];
            final user = getUserDisplay(
              data['user_name'],
              data['user_id'],
              data['reason'],
            );
            final action = data['event_type'] == 'LOCK' ? 'Fechar' : 'Abrir';
            final reason = translateReason(data['reason']);
            final newLog = {
              'data_hora': timestamp,
              'usuario': user,
              'acao': action,
              'reason': reason,
            };
            setState(() {
              logs.insert(0, newLog); // Add to beginning
            });
          }
        } catch (e) {
          // Ignore invalid messages
        }
      },
      onError: (error) {
        // Reconnect after delay
        Future.delayed(const Duration(seconds: 5), _connectWebSocket);
      },
      onDone: () {
        // Reconnect
        Future.delayed(const Duration(seconds: 5), _connectWebSocket);
      },
    );

    // Initial polls
    await _pollDevice();
    await _pollLogs();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppInForeground = state == AppLifecycleState.resumed;
  }

  Future<void> _pollDevice() async {
    final backendToken = await LocalService.getBackendToken();
    if (backendToken == null) return;

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final deviceResponse = await http.get(
          Uri.parse('${LocalService.backendUrl}/device/${widget.fechaduraId}'),
          headers: {'Authorization': 'Bearer $backendToken'},
        );
        if (deviceResponse.statusCode == 200) {
          final deviceData = jsonDecode(deviceResponse.body);
          print('DEBUG: Polled device data: $deviceData');

          // Update fechadura with latest locked_down_at
          if (fechadura != null) {
            fechadura!['locked_down_at'] = deviceData['locked_down_at'];
          }

          final newIsOpen = deviceData['lock_state'] == 'UNLOCKED';
          final newLastHeard = deviceData['last_heard'];
          setState(() {
            isOpen = newIsOpen;
            lastHeard = newLastHeard;
          });
        }
        break;
      } catch (e) {
        if (attempt == 1) {
          // Ignore
        } else {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    // Poll ping if connected
    if (isConnected) {
      final start = DateTime.now().millisecondsSinceEpoch;
      final pingResponse = await http.post(
        Uri.parse('${LocalService.backendUrl}/ping/${widget.fechaduraId}'),
        headers: {'Authorization': 'Bearer $backendToken'},
      );
      if (pingResponse.statusCode == 200) {
        final end = DateTime.now().millisecondsSinceEpoch;
        final newPingMs = ((end - start) / 2).round();
        setState(() {
          pingMs = newPingMs;
        });
      }
    }
  }

  Future<void> _pollLogs() async {
    final backendToken = await LocalService.getBackendToken();
    if (backendToken == null) return;

    try {
      final logsResponse = await http.get(
        Uri.parse('${LocalService.backendUrl}/logs/${widget.fechaduraId}'),
        headers: {'Authorization': 'Bearer $backendToken'},
      );
      if (logsResponse.statusCode == 200) {
        final logsData = jsonDecode(logsResponse.body) as List;
        final transformedLogs = logsData.map((log) {
          final timestamp = DateTime.parse(
            log['timestamp'],
          ).millisecondsSinceEpoch;
          final user = getUserDisplay(
            log['user_name'],
            log['user_id'],
            log['reason'],
          );
          final action = log['event_type'] == 'LOCK' ? 'Fechar' : 'Abrir';
          final reason = translateReason(log['reason']);
          return {
            'data_hora': timestamp,
            'usuario': user,
            'acao': action,
            'reason': reason,
          };
        }).toList();
        setState(() {
          logs = transformedLogs;
        });
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _carregarDadosFechadura() async {
    print('DEBUG: Starting _carregarDadosFechadura');
    try {
      final usuario = await LocalService.getUsuarioLogado();
      bool admin = false;
      String userId = '';
      if (usuario != null) {
        userId = usuario['id'] as String;
      }
      final doc = await FirebaseFirestore.instance
          .collection('fechaduras')
          .doc(userId)
          .collection('devices')
          .doc(widget.fechaduraId)
          .get();
      final f = doc.exists ? doc.data() : null;
      print('DEBUG: f: $f');

      // Verificar se é dono (se o doc existe sob o user_id)
      admin = doc.exists;
      // TODO: Check administrators from Firestore if needed

      // Fetch lock state and logs from backend
      final backendToken = await LocalService.getBackendToken();
      if (backendToken != null) {
        // Fetch device state
        final deviceResponse = await http.get(
          Uri.parse('${LocalService.backendUrl}/device/${widget.fechaduraId}'),
          headers: {'Authorization': 'Bearer $backendToken'},
        );
        if (deviceResponse.statusCode == 200) {
          final deviceData = jsonDecode(deviceResponse.body);
          print('DEBUG: deviceData: $deviceData');
          isOpen = deviceData['lock_state'] == 'UNLOCKED';
          lastHeard = deviceData['last_heard'];
          _wifiSsidController.text = deviceData['wifi_ssid'] ?? '';
          _wifiPasswordController.text =
              ''; // Don't populate password for security
          _audioTimeoutController.text =
              (deviceData['audio_record_timeout_sec'] ?? 10).toString();
          _lockTimeoutController.text =
              ((deviceData['lock_timeout_ms'] ?? 5000) ~/ 1000)
                  .toString(); // Convert ms to seconds for display
          _pairingTimeoutController.text =
              (deviceData['pairing_timeout_sec'] ?? 300).toString();
          _voiceDetectionEnabled = deviceData['voice_detection_enable'] ?? true;
          _voiceInviteEnabled = deviceData['voice_invite_enable'] ?? true;
          _voiceThreshold = (deviceData['voice_threshold'] ?? 0.60).toDouble();
          _vadRmsThreshold = deviceData['vad_rms_threshold'] ?? 1000;
          _initialVoiceDetectionEnabled = _voiceDetectionEnabled;
          _initialVoiceInviteEnabled = _voiceInviteEnabled;
          _initialVoiceThreshold = _voiceThreshold;
          _initialVadRmsThreshold = _vadRmsThreshold;

          // Store initial values
          _initialWifiSsid = _wifiSsidController.text;
          _initialAudioTimeout = _audioTimeoutController.text;
          _initialLockTimeout = _lockTimeoutController.text;
          _initialPairingTimeout = _pairingTimeoutController.text;
          _initialVoiceThreshold = _voiceThreshold;

          // Update fechadura with locked_down_at
          if (f != null) {
            f['locked_down_at'] = deviceData['locked_down_at'];
          }
        }

        final logsResponse = await http.get(
          Uri.parse('${LocalService.backendUrl}/logs/${widget.fechaduraId}'),
          headers: {'Authorization': 'Bearer $backendToken'},
        );
        if (logsResponse.statusCode == 200) {
          final logsData = jsonDecode(logsResponse.body) as List;
          print('DEBUG: logsData length: ${logsData.length}');
          // Transform to map format: {id, device_id, timestamp, event_type, reason, user_id, user_name}
          final transformedLogs = logsData.map((log) {
            print('DEBUG: processing log: $log');
            final timestamp = DateTime.parse(
              log['timestamp'],
            ).millisecondsSinceEpoch;
            final user = getUserDisplay(
              log['user_name'],
              log['user_id'],
              log['reason'],
            );
            print('DEBUG: user: $user');
            final action = log['event_type'] == 'LOCK' ? 'Fechar' : 'Abrir';
            final reason = translateReason(log['reason']);
            return {
              'data_hora': timestamp,
              'usuario': user,
              'acao': action,
              'reason': reason,
            };
          }).toList();
          logs = transformedLogs;
          print('DEBUG: logs set, length: ${logs.length}');
        }
      }

      setState(() {
        fechadura = f;
        administrador = admin;
        notificationsEnabled = f?['notificacoes'] == 1;
        // isOpen is set from backend above
        _isLoading = false;
      });
      _nomeController.text = f?['nome'] ?? '';
    } catch (e) {
      print('Erro ao carregar fechadura: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _registrarAcao(String acao) async {
    try {
      final usuario = await LocalService.getUsuarioLogado();
      final usuarioNome = usuario?['nome'] ?? 'Usuário';
      final agora = DateTime.now().millisecondsSinceEpoch;
      final novoEstado = acao == 'Abrir' ? 1 : 0;

      final userId = usuario?['id'] as String;
      final backendToken = await LocalService.getBackendToken();

      if (backendToken == null) {
        throw Exception('No backend token');
      }

      // Call backend for control
      final command = acao == 'Abrir' ? 'UNLOCK' : 'LOCK';
      final url = '${LocalService.backendUrl}/control/${widget.fechaduraId}';
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

      // Update Firebase for notifications and logs
      await FirebaseFirestore.instance
          .collection('fechaduras')
          .doc(userId)
          .collection('devices')
          .doc(widget.fechaduraId)
          .update({'notificacoes': notificationsEnabled ? 1 : 0});

      await FirebaseFirestore.instance.collection('logs_acesso').add({
        'fechadura_id': widget.fechaduraId,
        'usuario': usuarioNome,
        'acao': acao, // "Abrir" ou "Fechar"
        'data_hora': agora,
        'tipo_acesso': 'manual', // ou 'remoto' conforme seu fluxo
      });

      // WebSocket will update state
      setState(() {
        isOpen = novoEstado == 1;
      });

      // Mostra feedback para o usuário
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fechadura ${novoEstado == 1 ? 'abriu' : 'fechou'} com sucesso!',
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

  String _formatarHorario(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic>? get _ultimoLog {
    if (logs.isEmpty) return null;
    // Cria uma cópia da lista, ordena a cópia e retorna o último
    return ([...logs]..sort(
          (a, b) => (a['data_hora'] as int).compareTo(b['data_hora'] as int),
        ))
        .last;
  }

  IconData _getIconeFechadura() {
    if (fechadura == null) return Icons.lock;

    final codePoint = fechadura!['icone_code_point'];
    if (codePoint == null || codePoint == 0) return Icons.lock;

    return IconData(codePoint, fontFamily: 'MaterialIcons');
  }

  static const List<IconData> availableIcons = [
    Icons.star,
    Icons.home,
    Icons.lock,
    Icons.security,
    Icons.door_front_door,
    Icons.key,
    Icons.science, // lab
    Icons.house,
    Icons.dns, // server rack
    Icons.cabin,
    Icons.hotel,
    Icons.store,
    Icons.shop,
    Icons.restaurant,
    Icons.school,
    Icons.church,
    Icons.computer,
    Icons.warehouse,
  ];

  Widget _buildIconOption(
    IconData icon,
    IconData selectedIcon,
    StateSetter setStateDialog,
    Function(IconData) onSelected,
  ) {
    return GestureDetector(
      onTap: () {
        setStateDialog(() {
          onSelected(icon);
        });
      },
      child: SizedBox(
        width: 46,
        height: 46,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(
              color: selectedIcon == icon ? Colors.white : Colors.grey,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: selectedIcon == icon ? Colors.white : Colors.grey,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _buildIconGrid({
    required IconData selectedIcon,
    required StateSetter setStateDialog,
    required ValueChanged<IconData> onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          crossAxisSpacing: 10,
          mainAxisSpacing: 7,
        ),
        itemCount: availableIcons.length,
        itemBuilder: (context, index) {
          final icon = availableIcons[index];
          return _buildIconOption(
            icon,
            selectedIcon,
            setStateDialog,
            onSelected,
          );
        },
      ),
    );
  }

  void _showEditDialog() {
    final TextEditingController nomeController = TextEditingController(
      text: fechadura?['nome'] ?? '',
    );
    IconData selectedIcon = _getIconeFechadura();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(24),
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
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Editar Fechadura',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: nomeController,
                            style: TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Nome da Fechadura',
                              labelStyle: TextStyle(color: Colors.white70),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white54),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Selecione um ícone:',
                            style: TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          _buildIconGrid(
                            selectedIcon: selectedIcon,
                            setStateDialog: setStateDialog,
                            onSelected: (icon) => selectedIcon = icon,
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _GlassButton(
                                onPressed: () => Navigator.of(context).pop(),
                                text: 'Cancelar',
                                color: Colors.red,
                                width: 120,
                                height: 50,
                              ),
                              _GlassButton(
                                onPressed: () async {
                                  final nome = nomeController.text.trim();
                                  final usuario =
                                      await LocalService.getUsuarioLogado();
                                  final userId = usuario?['id'] as String;
                                  if (userId != null) {
                                    await FirebaseFirestore.instance
                                        .collection('fechaduras')
                                        .doc(userId)
                                        .collection('devices')
                                        .doc(widget.fechaduraId)
                                        .update({
                                          'nome': nome,
                                          'icone_code_point':
                                              selectedIcon.codePoint,
                                        });
                                    setState(() {
                                      fechadura!['nome'] = nome;
                                      fechadura!['icone_code_point'] =
                                          selectedIcon.codePoint;
                                    });
                                  }
                                  Navigator.of(context).pop();
                                },
                                text: 'Confirmar',
                                color: Colors.green,
                                width: 120,
                                height: 50,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('images/Fundo9.jpg'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.0),
            BlendMode.srcOver,
          ),
        ),
      ),

      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            fechadura?['nome'] ?? 'Detalhes da Fechadura',
            style: TextStyle(color: Colors.white),
          ),

          iconTheme: IconThemeData(color: Colors.white, size: 30.0),

          centerTitle: true,
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              icon: Icon(Icons.edit, color: Colors.white, size: 30.0),
              onPressed: administrador ? () => _showEditDialog() : null,
            ),
            IconButton(
              icon: Icon(Icons.security, color: Colors.white, size: 30.0),
              onPressed: administrador
                  ? (isLockedDown
                        ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'A porta já está em modo de bloqueio!',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        : () => _showLockdownDialog())
                  : null,
            ),
          ],
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
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
                          color: Colors.transparent,
                          child: Icon(
                            _getIconeFechadura(),
                            size: 50,
                            color: Colors.white,
                          ),
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
                                      isConnected ? Icons.wifi : Icons.wifi_off,
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
                              if (!isLockedDown &&
                                  !isConnected &&
                                  lastHeard != null)
                                Row(
                                  children: [
                                    Icon(
                                      Icons.schedule,
                                      color: Colors.orange.shade800,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Última conexão: ${_formatarHorario(lastHeard!)}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              if (isLockedDown &&
                                  fechadura?['locked_down_at'] != null)
                                Row(
                                  children: [
                                    Icon(
                                      Icons.lock_clock,
                                      color: Colors.red,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Bloqueada em: ${_formatarHorario(fechadura!['locked_down_at'])}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              Text(
                                'Último acesso: ${_ultimoLog == null ? 'N/A' : '${_formatarHorario(_ultimoLog!['data_hora'] as int)} • '
                                          '${_ultimoLog!['usuario'] ?? 'Usuário'}'}',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
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
                        _GlassButton(
                          onPressed:
                              administrador && isConnected && !isLockedDown
                              ? () {
                                  final acao = isOpen ? 'Fechar' : 'Abrir';
                                  _registrarAcao(acao);
                                }
                              : null, // Desabilita se não for administrador, desconectado ou em lockdown
                          text: (isOpen ? 'Fechar' : 'Abrir'),
                          isEnabled:
                              administrador &&
                              isConnected &&
                              !isLockedDown, // Passa o estado para o widget
                        ),

                        _GlassButton(
                          onPressed: administrador
                              ? () {
                                  _mostrarDialogoConvite();
                                }
                              : null, // Desabilita se não for administrador
                          text: ('Convidar'),
                          isEnabled: administrador, // Sempre habilitado
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'Configurações:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    SwitchListTile(
                      title: Text(
                        'Notificações',
                        style: TextStyle(color: Colors.white),
                      ),
                      value: notificationsEnabled,
                      onChanged: (bool value) async {
                        setState(() {
                          notificationsEnabled = value;
                        });

                        final usuario = await LocalService.getUsuarioLogado();
                        final userId = usuario?['id'] as String;
                        await FirebaseFirestore.instance
                            .collection('fechaduras')
                            .doc(userId)
                            .collection('devices')
                            .doc(widget.fechaduraId)
                            .update({'notificacoes': value ? 1 : 0});
                      },
                      activeColor: Colors.blueAccent.withOpacity(0.5),
                      inactiveTrackColor: Colors.transparent,
                    ),

                    Text(
                      'Configurações do Dispositivo:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Form(
                      key: _configFormKey,
                      child: Column(
                        children: [
                          // Voice Configuration Card
                          ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 13, sigmaY: 13),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blueAccent.withOpacity(0.2),
                                      Colors.blueAccent.withOpacity(0.1),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.mic,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Configuração de Voz',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    SwitchListTile(
                                      title: Text(
                                        'Permitir controle por voz',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      value: _voiceDetectionEnabled,
                                      onChanged: (bool value) {
                                        setState(() {
                                          _voiceDetectionEnabled = value;
                                        });
                                      },
                                      activeColor: Colors.blueAccent
                                          .withOpacity(0.5),
                                      inactiveTrackColor: Colors.transparent,
                                    ),
                                    const SizedBox(height: 16),
                                    SwitchListTile(
                                      title: Text(
                                        'Permitir voz de convidados',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      value: _voiceInviteEnabled,
                                      onChanged: (bool value) {
                                        setState(() {
                                          _voiceInviteEnabled = value;
                                        });
                                      },
                                      activeColor: Colors.blueAccent
                                          .withOpacity(0.5),
                                      inactiveTrackColor: Colors.transparent,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Limite de confiança de voz: ${(_voiceThreshold * 100).round()}%',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Slider(
                                      value: _voiceThreshold,
                                      min: 0.20,
                                      max: 0.90,
                                      divisions:
                                          7, // 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90
                                      label:
                                          '${(_voiceThreshold * 100).round()}%',
                                      activeColor: Colors.blueAccent
                                          .withOpacity(0.5),
                                      inactiveColor: Colors.white.withOpacity(
                                        0.3,
                                      ),
                                      onChanged: (double value) {
                                        setState(() {
                                          _voiceThreshold = value;
                                        });
                                      },
                                    ),
                                    Text(
                                      _getSecurityLabel(_voiceThreshold),
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Nível mínimo de áudio para ativar detecção de voz: $_vadRmsThreshold',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Slider(
                                      value:
                                          ((log(_vadRmsThreshold.toDouble()) /
                                                          log(10) -
                                                      log(500) / log(10)) /
                                                  (log(25000) / log(10) -
                                                      log(500) / log(10)) *
                                                  100)
                                              .clamp(0, 100),
                                      min: 0,
                                      max: 100,
                                      divisions: 20,
                                      label: '$_vadRmsThreshold',
                                      activeColor: Colors.blueAccent
                                          .withOpacity(0.5),
                                      inactiveColor: Colors.white.withOpacity(
                                        0.3,
                                      ),
                                      onChanged: (double sliderValue) {
                                        double minLog = log(500) / log(10);
                                        double maxLog = log(25000) / log(10);
                                        double logValue =
                                            minLog +
                                            (sliderValue / 100) *
                                                (maxLog - minLog);
                                        int newValue = pow(
                                          10,
                                          logValue,
                                        ).round();
                                        setState(() {
                                          _vadRmsThreshold = newValue.clamp(
                                            500,
                                            25000,
                                          );
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // WiFi Configuration Card
                          // WiFi Configuration Card
                          ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 13, sigmaY: 13),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blueAccent.withOpacity(0.2),
                                      Colors.blueAccent.withOpacity(0.1),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.wifi,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Configuração WiFi',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _wifiSsidController,
                                      style: TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: 'Nome da Rede (SSID)',
                                        labelStyle: TextStyle(
                                          color: Colors.white70,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: Colors.white54,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'SSID não pode ser vazio';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _wifiPasswordController,
                                      style: TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: 'Senha (opcional)',
                                        labelStyle: TextStyle(
                                          color: Colors.white70,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: Colors.white54,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      obscureText: true,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Timeouts Configuration Card
                          ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 13, sigmaY: 13),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blueAccent.withOpacity(0.2),
                                      Colors.blueAccent.withOpacity(0.1),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.timer,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Configuração de Tempos',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: _audioTimeoutController,
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            decoration: InputDecoration(
                                              labelText: 'Gravação Áudio (s)',
                                              labelStyle: TextStyle(
                                                color: Colors.white70,
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderSide: BorderSide(
                                                  color: Colors.white54,
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderSide: BorderSide(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            validator: (value) {
                                              if (value == null ||
                                                  value.isEmpty) {
                                                return 'Campo obrigatório';
                                              }
                                              final num = int.tryParse(value);
                                              if (num == null ||
                                                  num < 3 ||
                                                  num > 10) {
                                                return '3-10s';
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: TextFormField(
                                            controller: _lockTimeoutController,
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            decoration: InputDecoration(
                                              labelText: 'Trava (s)',
                                              labelStyle: TextStyle(
                                                color: Colors.white70,
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderSide: BorderSide(
                                                  color: Colors.white54,
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderSide: BorderSide(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            validator: (value) {
                                              if (value == null ||
                                                  value.isEmpty) {
                                                return 'Campo obrigatório';
                                              }
                                              final num = int.tryParse(value);
                                              if (num == null ||
                                                  num < 5 ||
                                                  num > 300) {
                                                return '5-300s';
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _pairingTimeoutController,
                                      style: TextStyle(color: Colors.white),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      decoration: InputDecoration(
                                        labelText: 'Modo Pareamento (s)',
                                        labelStyle: TextStyle(
                                          color: Colors.white70,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: Colors.white54,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Campo obrigatório';
                                        }
                                        final num = int.tryParse(value);
                                        if (num == null ||
                                            num < 60 ||
                                            num > 600) {
                                          return '60-600s';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _GlassButton(
                                onPressed: administrador && isConnected
                                    ? () => _salvarConfiguracoes()
                                    : null,
                                text: 'Salvar',
                                isEnabled: administrador && isConnected,
                                width: 150,
                              ),
                              _GlassButton(
                                onPressed: administrador && isConnected
                                    ? () => _reiniciarDispositivo()
                                    : null,
                                text: 'Reiniciar',
                                isEnabled: administrador && isConnected,
                                width: 150,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      'Histórico de Acessos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    Padding(padding: EdgeInsets.only(bottom: 15)),

                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),

                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 13, sigmaY: 13),

                          child: Container(
                            width: MediaQuery.of(context).size.width * 0.9,
                            height: MediaQuery.of(context).size.height * 0.78,
                            padding: const EdgeInsets.all(30),
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

                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.9,
                              ),

                              child: Column(
                                children: [
                                  // CORPO SCROLLÁVEL
                                  Expanded(
                                    child: logs.isEmpty
                                        ? Center(
                                            child: Padding(
                                              padding: EdgeInsets.all(20),
                                              child: Text(
                                                'Nenhum log disponível',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                          )
                                        : SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: DataTable(
                                              columns: const [
                                                DataColumn(
                                                  label: Text(
                                                    'Horário',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                DataColumn(
                                                  label: Text(
                                                    'Responsável',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                DataColumn(
                                                  label: Text(
                                                    'Ação',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                DataColumn(
                                                  label: Text(
                                                    'Motivo',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              rows: logs.map((log) {
                                                final horario =
                                                    _formatarHorario(
                                                      log['data_hora'] as int,
                                                    );

                                                return DataRow(
                                                  cells: [
                                                    DataCell(
                                                      Text(
                                                        horario,
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                    DataCell(
                                                      Text(
                                                        log['usuario'] ?? 'N/A',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                    DataCell(
                                                      Text(
                                                        log['acao'] ?? 'N/A',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                    DataCell(
                                                      Text(
                                                        log['reason'] ?? 'N/A',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              }).toList(),
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
                  ],
                ),
              ),
      ),
    );
  }

  void _showLockdownDialog() {
    bool confirmed = false;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.orangeAccent.withOpacity(0.4),
                          Colors.yellow.withOpacity(0.2),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.orangeAccent.withOpacity(0.5),
                        width: 3,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ativar Modo de Bloqueio de Emergência',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Uma vez ativado, o modo de bloqueio só pode ser desativado acessando fisicamente o lado seguro da porta e reiniciando o dispositivo manualmente.',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Checkbox(
                              value: confirmed,
                              onChanged: (value) {
                                setStateDialog(() {
                                  confirmed = value ?? false;
                                });
                              },
                              activeColor: Colors.blue,
                              side: BorderSide(color: Colors.white, width: 2),
                            ),
                            Expanded(
                              child: Text(
                                'Li e entendi as consequências',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _GlassButton(
                              onPressed: () => Navigator.of(context).pop(),
                              text: 'Cancelar',
                              color: Colors.blue,
                              width: 120,
                              height: 50,
                            ),
                            _GlassButton(
                              onPressed: () {
                                if (confirmed) {
                                  Navigator.of(context).pop();
                                  _activateLockdown();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Marque a caixa de confirmação primeiro.',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                              text: 'Confirmar',
                              color: confirmed ? Colors.red : Colors.grey,
                              width: 120,
                              height: 50,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _activateLockdown() async {
    try {
      final backendToken = await LocalService.getBackendToken();
      if (backendToken == null) {
        throw Exception('No backend token');
      }

      final response = await http.post(
        Uri.parse('${LocalService.backendUrl}/lockdown/${widget.fechaduraId}'),
        headers: {
          'Authorization': 'Bearer $backendToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Backend error: ${response.statusCode}');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modo de bloqueio ativado com sucesso!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao ativar modo de bloqueio: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _mostrarDialogoConvite() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(24),
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
                    child: Form(
                      key: _conviteFormKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Convidar Usuário',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Campo email do usuário
                          TextFormField(
                            controller: _idUsuarioController,
                            style: TextStyle(color: Colors.white),
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Digite o e-mail do usuário';
                              }
                              // Basic email validation
                              if (!value.contains('@') ||
                                  !value.contains('.')) {
                                return 'Digite um e-mail válido';
                              }
                              return null;
                            },
                            decoration: InputDecoration(
                              labelText: 'E-mail do Usuário',
                              hintText: 'Ex: usuario@email.com',
                              labelStyle: TextStyle(color: Colors.white70),
                              hintStyle: TextStyle(color: Colors.white54),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white54),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.red),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Dropdown duração
                          DropdownButtonFormField<String>(
                            value: _duracaoSelecionada,
                            style: TextStyle(color: Colors.white),
                            dropdownColor: Colors.blueGrey.shade800,
                            decoration: InputDecoration(
                              labelText: 'Duração do Convite',
                              labelStyle: TextStyle(color: Colors.white70),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white54),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '2_dias',
                                child: Text('2 Dias'),
                              ),
                              DropdownMenuItem(
                                value: '1_semana',
                                child: Text('1 Semana'),
                              ),
                              DropdownMenuItem(
                                value: '2_semanas',
                                child: Text('2 Semanas'),
                              ),
                              DropdownMenuItem(
                                value: '1_mes',
                                child: Text('1 Mês'),
                              ),
                              DropdownMenuItem(
                                value: 'permanente',
                                child: Text('Permanente'),
                              ),
                            ],
                            onChanged: (value) {
                              setDialogState(() {
                                _duracaoSelecionada = value!;
                              });
                            },
                          ),
                          const SizedBox(height: 16),

                          // Botões
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _GlassButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _limparFormularioConvite();
                                },
                                text: ('Cancelar'),
                                color: Colors.red,
                                width: 120,
                                height: 50,
                              ),

                              _GlassButton(
                                onPressed: () {
                                  if (_conviteFormKey.currentState!
                                      .validate()) {
                                    _enviarConvite();
                                    Navigator.of(context).pop();
                                  }
                                },
                                text: ('Enviar'),
                                color: Colors.green,
                                width: 120,
                                height: 50,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _enviarConvite() async {
    try {
      final emailUsuario = _idUsuarioController.text.trim();

      // Call backend to create invite
      final backendToken = await LocalService.getBackendToken();
      if (backendToken == null) {
        _mostrarErro('Erro de autenticação');
        return;
      }

      final response = await http.post(
        Uri.parse('${LocalService.backendUrl}/create_invite'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $backendToken',
        },
        body: jsonEncode({
          'receiver_email': emailUsuario,
          'device_id': widget.fechaduraId,
          'expiry_duration': _duracaoSelecionada,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        _mostrarSucesso('Convite enviado com sucesso!');
        _limparFormularioConvite();
      } else if (response.statusCode == 404) {
        _mostrarErro('Usuário com este e-mail não encontrado');
      } else if (response.statusCode == 409) {
        _mostrarErro('Já existe um convite pendente para este usuário');
      } else {
        _mostrarErro('Erro ao enviar convite: ${response.statusCode}');
      }
    } catch (e) {
      _mostrarErro('Erro ao enviar convite: $e');
    }
  }

  DateTime _calcularDataExpiracao(DateTime dataBase, String duracao) {
    switch (duracao) {
      case '2_dias':
        return dataBase.add(Duration(days: 2));
      case '1_semana':
        return dataBase.add(Duration(days: 7));
      case '2_semanas':
        return dataBase.add(Duration(days: 14));
      case '1_mes':
        return dataBase.add(Duration(days: 30));
      case 'permanente':
        return dataBase.add(Duration(days: 36500)); // 100 anos
      default:
        return dataBase.add(Duration(days: 7));
    }
  }

  void _limparFormularioConvite() {
    _idUsuarioController.clear();
    _duracaoSelecionada = '1_semana';
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

  Future<void> _salvarConfiguracoes() async {
    if (!_configFormKey.currentState!.validate()) {
      return;
    }

    try {
      final backendToken = await LocalService.getBackendToken();
      if (backendToken == null) {
        _mostrarErro('Erro de autenticação');
        return;
      }

      final configs = <Map<String, String>>[];

      // Only add modified fields
      if (_wifiSsidController.text != _initialWifiSsid) {
        configs.add({'key': 'wifi_ssid', 'value': _wifiSsidController.text});
      }
      if (_wifiPasswordController.text.isNotEmpty) {
        configs.add({
          'key': 'wifi_pass',
          'value': _wifiPasswordController.text,
        });
      }
      if (_audioTimeoutController.text != _initialAudioTimeout) {
        configs.add({
          'key': 'audio_timeout',
          'value': _audioTimeoutController.text,
        });
      }
      if (_lockTimeoutController.text != _initialLockTimeout) {
        configs.add({
          'key': 'lock_timeout',
          'value': (int.parse(_lockTimeoutController.text) * 1000).toString(),
        });
      }
      if (_pairingTimeoutController.text != _initialPairingTimeout) {
        configs.add({
          'key': 'pairing_timeout',
          'value': _pairingTimeoutController.text,
        });
      }
      if (_voiceDetectionEnabled != _initialVoiceDetectionEnabled) {
        configs.add({
          'key': 'voice_detection_enable',
          'value': _voiceDetectionEnabled ? '1' : '0',
        });
      }
      if (_voiceInviteEnabled != _initialVoiceInviteEnabled) {
        configs.add({
          'key': 'voice_invite_enable',
          'value': _voiceInviteEnabled ? '1' : '0',
        });
      }
      if (_voiceThreshold != _initialVoiceThreshold) {
        configs.add({
          'key': 'voice_threshold',
          'value': _voiceThreshold.toStringAsFixed(2),
        });
      }
      if (_vadRmsThreshold != _initialVadRmsThreshold) {
        configs.add({
          'key': 'vad_rms_threshold',
          'value': _vadRmsThreshold.toString(),
        });
      }

      if (configs.isEmpty) {
        _mostrarSucesso('Nenhuma alteração detectada.');
        return;
      }

      final response = await http.post(
        Uri.parse(
          '${LocalService.backendUrl}/update_config/${widget.fechaduraId}',
        ),
        headers: {
          'Authorization': 'Bearer $backendToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'configs': configs}),
      );

      if (response.statusCode == 200) {
        _mostrarSucesso('Configurações salvas com sucesso.');
        // Update initial values after successful save
        _initialWifiSsid = _wifiSsidController.text;
        _initialAudioTimeout = _audioTimeoutController.text;
        _initialLockTimeout = _lockTimeoutController.text;
        _initialPairingTimeout = _pairingTimeoutController.text;
        _initialVoiceDetectionEnabled = _voiceDetectionEnabled;
        _initialVoiceInviteEnabled = _voiceInviteEnabled;
        _initialVoiceThreshold = _voiceThreshold;
      } else {
        _mostrarErro('Erro ao salvar configurações: ${response.statusCode}');
      }
    } catch (e) {
      _mostrarErro('Erro ao salvar configurações: $e');
    }
  }

  String _getSecurityLabel(double threshold) {
    if (threshold >= 0.75) {
      return 'Muito seguro (pode causar falsos negativos frequentes)';
    } else if (threshold >= 0.60) {
      return 'Seguro (equilíbrio ideal)';
    } else if (threshold >= 0.40) {
      return 'Moderadamente seguro (fácil de enganar com gravações)';
    } else if (threshold >= 0.30) {
      return 'Inseguro';
    } else {
      return 'Muito inseguro (altamente recomendável aumentar)';
    }
  }

  Future<void> _reiniciarDispositivo() async {
    try {
      final backendToken = await LocalService.getBackendToken();
      if (backendToken == null) {
        _mostrarErro('Erro de autenticação');
        return;
      }

      final response = await http.post(
        Uri.parse('${LocalService.backendUrl}/reboot/${widget.fechaduraId}'),
        headers: {
          'Authorization': 'Bearer $backendToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'command': 'REBOOT',
          'user_id': (await LocalService.getUsuarioLogado())?['id'],
        }),
      );

      if (response.statusCode == 200) {
        _mostrarSucesso('Dispositivo reiniciando...');
      } else {
        _mostrarErro('Erro ao reiniciar dispositivo: ${response.statusCode}');
      }
    } catch (e) {
      _mostrarErro('Erro ao reiniciar dispositivo: $e');
    }
  }

  @override
  void dispose() {
    _webSocketChannel?.sink.close(status.goingAway);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _GlassButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isEnabled;
  final Color color;
  final double width;
  final double height;

  const _GlassButton({
    required this.text,
    required this.onPressed,
    this.isEnabled = true,
    this.color = Colors.blueAccent,
    this.width = 150,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),

        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),

          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isEnabled
                    ? [color.withOpacity(0.3), color.withOpacity(0.1)]
                    : [
                        Colors.grey.withOpacity(0.3),
                        Colors.grey.withOpacity(0.1),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: isEnabled
                    ? Colors.white.withOpacity(0.3)
                    : Colors.grey.withOpacity(0.3),
                width: 1,
              ),
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
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
