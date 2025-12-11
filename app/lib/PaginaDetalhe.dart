import 'package:flutter/material.dart';
import 'models/LocalService.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

const String backendUrl = 'http://192.168.0.75:12223';

class LockDetails extends StatefulWidget {
  final String fechaduraId;

  LockDetails({super.key, required this.fechaduraId});

  @override
  State<LockDetails> createState() => _LockDetailsState();
}

class _LockDetailsState extends State<LockDetails> {
  bool notificationsEnabled = true;
  bool remoteAccessEnabled = false;
  bool administrador = true;
  bool isOpen = true;
  bool _isAdmin = false;
  bool _isLoading = true;
  Map<String, dynamic>? fechadura;
  List<Map<String, dynamic>> logs = [];
  String _duracaoSelecionada = '1_semana';
  final _conviteFormKey = GlobalKey<FormState>();
  final _idUsuarioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarDadosFechadura();
  }

  Future<void> _carregarDadosFechadura() async {
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

      // Verificar se é dono (se o doc existe sob o user_id)
      admin = doc.exists;
      // TODO: Check administrators from Firestore if needed

      final querySnapshot = await FirebaseFirestore.instance
          .collection('logs_acesso')
          .where('fechadura_id', isEqualTo: widget.fechaduraId)
          .orderBy('data_hora', descending: true)
          .get();
      final logsData = querySnapshot.docs.map((doc) => doc.data()).toList();

      setState(() {
        fechadura = f;
        logs = logsData;
        administrador = admin; // Agora usa a verificação dupla
        notificationsEnabled = f?['notificacoes'] == 1;
        remoteAccessEnabled = f?['acesso_remoto'] == 1;
        isOpen = f?['aberto'] == 1;
        _isLoading = false;
      });
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
      final url = '$backendUrl/control/${widget.fechaduraId}';
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

      // Recarrega os logs para refletir na UI
      final querySnapshot = await FirebaseFirestore.instance
          .collection('logs_acesso')
          .where('fechadura_id', isEqualTo: widget.fechaduraId)
          .orderBy('data_hora', descending: true)
          .get();
      final logsData = querySnapshot.docs.map((doc) => doc.data()).toList();
      setState(() {
        logs = List<Map<String, dynamic>>.from(logsData);
        isOpen = novoEstado == 1; // Atualiza o estado local
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
            'Detalhes da Fechadura',
            style: TextStyle(color: Colors.white),
          ),

          iconTheme: IconThemeData(color: Colors.white, size: 30.0),

          centerTitle: true,
          backgroundColor: Colors.transparent,
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
                        Text(
                          'Status: ${isOpen ? 'Aberta' : 'Fechada'}',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                        Text(
                          'Conectada: Sim',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                        Text(
                          'Último acesso: ${_ultimoLog == null ? 'N/A' : '${_formatarHorario(_ultimoLog!['data_hora'] as int)} • '
                                    '${_ultimoLog!['usuario'] ?? 'Usuário'} • '
                                    '${_ultimoLog!['acao'] ?? ''}'}',
                          style: TextStyle(fontSize: 16, color: Colors.white),
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
                    onPressed: remoteAccessEnabled
                        ? () {
                            final acao = isOpen ? 'Fechar' : 'Abrir';
                            _registrarAcao(acao);
                          }
                        : null, // Desabilita se acesso remoto estiver off
                    text: (isOpen ? 'Fechar' : 'Abrir'),
                    isEnabled:
                        remoteAccessEnabled, // Passa o estado para o widget
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

              SwitchListTile(
                title: Text(
                  'Acesso remoto',
                  style: TextStyle(color: Colors.white),
                ),
                value: remoteAccessEnabled,
                onChanged: administrador
                    ? (bool value) async {
                        setState(() {
                          remoteAccessEnabled = value;
                        });

                        final usuario = await LocalService.getUsuarioLogado();
                        final userId = usuario?['id'] as String;
                        await FirebaseFirestore.instance
                            .collection('fechaduras')
                            .doc(userId)
                            .collection('devices')
                            .doc(widget.fechaduraId)
                            .update({
                              'acesso_remoto': remoteAccessEnabled ? 1 : 0,
                            });
                      }
                    : null, // Desabilita se não for administrador

                activeColor: administrador
                    ? Colors.blueAccent.withOpacity(0.5)
                    : Colors.grey,

                inactiveTrackColor: Colors.transparent,
              ),
              const SizedBox(height: 20),

              Text(
                'Logs de Acessos:',
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
                          maxWidth: MediaQuery.of(context).size.width * 0.9,
                        ),

                        child: Column(
                          children: [
                            // CABEÇALHO FIXO
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Text(
                                        'Horário',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Text(
                                        'Conta',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Text(
                                        '   Ação',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

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
                                  : ListView.builder(
                                      itemCount: logs.length,
                                      itemBuilder: (context, index) {
                                        final log = logs[index];
                                        final horario = _formatarHorario(
                                          log['data_hora'] as int,
                                        );

                                        return Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.white.withOpacity(
                                                  0.1,
                                                ),
                                                width: 0.5,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  horario,
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  log['usuario'] ?? 'N/A',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  '     ${log['acao'] ?? 'N/A'}',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
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

                          // Campo ID do usuário
                          TextFormField(
                            controller: _idUsuarioController,
                            style: TextStyle(color: Colors.white),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Digite o ID do usuário';
                              }
                              if (int.tryParse(value) == null) {
                                return 'Digite um número válido';
                              }
                              return null;
                            },
                            decoration: InputDecoration(
                              labelText: 'ID do Usuário',
                              hintText: 'Ex: 123',
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

                          // Switch Administrador
                          SwitchListTile(
                            title: Text(
                              'Permissões de Administrador',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Text(
                              _isAdmin
                                  ? 'Pode convidar outros e alterar configurações'
                                  : 'Apenas acesso básico',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            value: _isAdmin,
                            onChanged: (value) {
                              setDialogState(() {
                                _isAdmin = value;
                              });
                            },
                            activeColor: Colors.blueAccent,
                            inactiveTrackColor: Colors.white24,
                          ),
                          const SizedBox(height: 24),

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
      final usuarioId = _idUsuarioController.text;
      final usuario = await LocalService.getUsuarioLogado();
      final remetenteId = usuario?['id'] ?? '';

      // Verificar se o usuário existe
      final usuarioDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(usuarioId.toString())
          .get();
      final usuarioConvidado = usuarioDoc.exists ? usuarioDoc.data() : null;
      if (usuarioConvidado == null) {
        _mostrarErro('Usuário com ID $usuarioId não encontrado');
        return;
      }

      // Verificar se já não é administrador
      final adminSnapshot = await FirebaseFirestore.instance
          .collection('administradores_fechaduras')
          .where('fechadura_id', isEqualTo: widget.fechaduraId)
          .where('usuario_id', isEqualTo: usuarioId)
          .get();
      if (adminSnapshot.docs.isNotEmpty) {
        _mostrarErro('Este usuário já é administrador da fechadura');
        return;
      }

      // Verificar se já não existe convite pendente
      final convitesSnapshot = await FirebaseFirestore.instance
          .collection('convites')
          .where('fechadura_id', isEqualTo: widget.fechaduraId)
          .get();
      final convitesExistentes = convitesSnapshot.docs
          .map((doc) => doc.data())
          .toList();
      final convitePendente = convitesExistentes.any(
        (c) => c['destinatario_id'] == usuarioId && c['status'] == 0,
      );

      if (convitePendente) {
        _mostrarErro('Já existe um convite pendente para este usuário');
        return;
      }

      // Calcular data de expiração
      final agora = DateTime.now();
      final dataExpiracao = _calcularDataExpiracao(agora, _duracaoSelecionada);

      // Inserir convite no Firestore
      await FirebaseFirestore.instance.collection('convites').add({
        'fechadura_id': widget.fechaduraId,
        'remetente_id': remetenteId,
        'destinatario_id': usuarioId,
        'data_convite': agora.millisecondsSinceEpoch,
        'data_expiracao': dataExpiracao.millisecondsSinceEpoch,
        'status': 0, // 0 = pendente, 1 = aceito, 2 = recusado
        'permissoes_admin': _isAdmin ? 1 : 0,
      });

      _mostrarSucesso('Convite enviado para ${usuarioConvidado['nome']}!');

      _limparFormularioConvite();
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
    _isAdmin = false;
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

  @override
  void dispose() {
    _idUsuarioController.dispose();
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
                          content: Text('Opção desabilitada'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
              child: Center(
                child: Text(
                  text,
                  style: TextStyle(
                    color: isEnabled ? Colors.white : Colors.grey[400],
                    fontSize: 20,
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
