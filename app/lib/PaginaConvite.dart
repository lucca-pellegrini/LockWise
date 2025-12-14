import 'package:flutter/material.dart';
import 'LocalService.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class PaginaConvites extends StatefulWidget {
  const PaginaConvites({super.key});

  @override
  State<PaginaConvites> createState() => _PaginaConvitesState();
}

class _PaginaConvitesState extends State<PaginaConvites>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _convitesEnviados = [];
  List<Map<String, dynamic>> _convitesRecebidos = [];
  Map<String, dynamic>? _usuario;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _carregarDados();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);

    try {
      _usuario = await LocalService.getUsuarioLogado();

      if (_usuario != null) {
        final usuarioId = _usuario!['id'] as String;
        // Call backend to get invites
        final backendToken = await LocalService.getBackendToken();
        if (backendToken != null) {
          final response = await http.get(
            Uri.parse('${LocalService.backendUrl}/invites'),
            headers: {'Authorization': 'Bearer $backendToken'},
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final sentInvites = data['sent'] as List;
            final receivedInvites = data['received'] as List;

            // Transform to the expected format
            final enviados = sentInvites.map((invite) {
              final expiry = DateTime.fromMillisecondsSinceEpoch(
                invite['expiry_timestamp'] as int,
              );
              final created = DateTime.parse(invite['created_at'] as String);
              return {
                'id': invite['id'].toString(),
                'fechadura_id': invite['device_id'],
                'remetente_id': usuarioId,
                'destinatario_id': invite['receiver_id'],
                'status': invite['status'],
                'data_expiracao': expiry.millisecondsSinceEpoch,
                'data_convite': created.millisecondsSinceEpoch,
                'fechadura_nome':
                    'Fechadura ${invite['device_id']}', // TODO: get device name from Firestore
                'destinatario_nome': invite['receiver_name'] ?? 'Usuário',
                'destinatario_email': invite['receiver_email'] ?? '',
              };
            }).toList();

            final recebidos = receivedInvites.map((invite) {
              final expiry = DateTime.fromMillisecondsSinceEpoch(
                invite['expiry_timestamp'],
              );
              final created = DateTime.fromMillisecondsSinceEpoch(
                invite['created_at'],
              );
              return {
                'id': invite['id'].toString(),
                'fechadura_id': invite['device_id'],
                'remetente_id': invite['sender_id'],
                'status': invite['status'],
                'data_expiracao': expiry.millisecondsSinceEpoch,
                'data_convite': created.millisecondsSinceEpoch,
                'fechadura_nome':
                    'Fechadura ${invite['device_id']}', // TODO: get device name from Firestore
                'remetente_nome': invite['sender_name'] ?? 'Usuário',
                'remetente_email': invite['sender_email'] ?? '',
              };
            }).toList();

            // Fetch device names
            final deviceNames = <String, String>{};
            final deviceFetches = <Future>[];
            for (final convite in [...enviados, ...recebidos]) {
              final ownerId = convite['remetente_id'];
              final deviceId = convite['fechadura_id'];
              final key = '$ownerId:$deviceId';
              if (!deviceNames.containsKey(key)) {
                deviceFetches.add(
                  FirebaseFirestore.instance
                      .collection('fechaduras')
                      .doc(ownerId)
                      .collection('devices')
                      .doc(deviceId)
                      .get()
                      .then((doc) {
                        if (doc.exists) {
                          deviceNames[key] = doc.data()?['nome'] ?? 'Fechadura';
                        } else {
                          deviceNames[key] = 'Fechadura';
                        }
                      }),
                );
              }
            }
            await Future.wait(deviceFetches);

            // Update device names
            for (final convite in enviados) {
              final ownerId = convite['remetente_id'];
              final deviceId = convite['fechadura_id'];
              final key = '$ownerId:$deviceId';
              convite['fechadura_nome'] = deviceNames[key] ?? 'Fechadura';
            }
            for (final convite in recebidos) {
              final ownerId = convite['remetente_id'];
              final deviceId = convite['fechadura_id'];
              final key = '$ownerId:$deviceId';
              convite['fechadura_nome'] = deviceNames[key] ?? 'Fechadura';
            }

            setState(() {
              _convitesEnviados = enviados;
              _convitesRecebidos = recebidos;
              _isLoading = false;
            });
          } else {
            setState(() => _isLoading = false);
          }
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      print('Erro ao carregar convites: $e');
      setState(() => _isLoading = false);
    }
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
          title: Text('Convites', style: TextStyle(color: Colors.white)),
          iconTheme: IconThemeData(color: Colors.white, size: 30.0),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.blueAccent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Enviados'),
              Tab(text: 'Recebidos'),
            ],
          ),
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: Colors.blueAccent))
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildConvitesEnviados(),
                    _buildConvitesRecebidos(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildConvitesEnviados() {
    if (_convitesEnviados.isEmpty) {
      return _buildEmptyState('Nenhum convite enviado');
    }

    return ListView.builder(
      itemCount: _convitesEnviados.length,
      itemBuilder: (context, index) {
        final convite = _convitesEnviados[index];
        return _buildConviteEnviadoCard(convite);
      },
    );
  }

  Widget _buildConvitesRecebidos() {
    if (_convitesRecebidos.isEmpty) {
      return _buildEmptyState('Nenhum convite recebido');
    }

    return ListView.builder(
      itemCount: _convitesRecebidos.length,
      itemBuilder: (context, index) {
        final convite = _convitesRecebidos[index];
        return _buildConviteRecebidoCard(convite);
      },
    );
  }

  Widget _buildEmptyState(String mensagem) {
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
                Icon(Icons.mail_outline, size: 64, color: Colors.white54),
                SizedBox(height: 16),
                Text(
                  mensagem,
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConviteEnviadoCard(Map<String, dynamic> convite) {
    final dataExpiracao = DateTime.fromMillisecondsSinceEpoch(
      convite['data_expiracao'],
    );
    final dataCriacao = DateTime.fromMillisecondsSinceEpoch(
      convite['data_convite'],
    );
    final agora = DateTime.now();
    final expirou = agora.isAfter(dataExpiracao);
    final status = _getStatusConvite(convite['status'] as int, expirou);

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blueAccent.withOpacity(0.2),
                  Colors.blueAccent.withOpacity(0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            convite['fechadura_nome'],
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Para: ${convite['destinatario_nome']} (${convite['destinatario_email']})',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _editarDataExpiracao(convite),
                          icon: Icon(Icons.edit, color: Colors.white),
                          tooltip: 'Editar expiração',
                        ),
                        IconButton(
                          onPressed: () => _revogarConvite(convite),
                          icon: Icon(Icons.delete, color: Colors.red),
                          tooltip: 'Revogar convite',
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.schedule, color: Colors.white54, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Criado: ${_formatarData(dataCriacao)}',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      expirou ? Icons.warning : Icons.access_time,
                      color: expirou ? Colors.orange : Colors.white54,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Expira: ${_formatarData(dataExpiracao)}',
                      style: TextStyle(
                        color: expirou ? Colors.orange : Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: status['color'].withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: status['color'].withOpacity(0.5)),
                  ),
                  child: Text(
                    status['texto'],
                    style: TextStyle(
                      color: status['color'],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConviteRecebidoCard(Map<String, dynamic> convite) {
    final dataExpiracao = DateTime.fromMillisecondsSinceEpoch(
      convite['data_expiracao'],
    );
    final dataCriacao = DateTime.fromMillisecondsSinceEpoch(
      convite['data_convite'],
    );
    final agora = DateTime.now();
    final expirou = agora.isAfter(dataExpiracao);
    final status = _getStatusConvite(convite['status'] as int, expirou);
    final isPendente = convite['status'] == 0 && !expirou;

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blueAccent.withOpacity(0.2),
                  Colors.blueAccent.withOpacity(0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  convite['fechadura_nome'],
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'De: ${convite['remetente_nome']} (${convite['remetente_email']})',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.schedule, color: Colors.white54, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Recebido: ${_formatarData(dataCriacao)}',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      expirou ? Icons.warning : Icons.access_time,
                      color: expirou ? Colors.orange : Colors.white54,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Expira: ${_formatarData(dataExpiracao)}',
                      style: TextStyle(
                        color: expirou ? Colors.orange : Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: status['color'].withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: status['color'].withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        status['texto'],
                        style: TextStyle(
                          color: status['color'],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isPendente)
                      Row(
                        children: [
                          _GlassButton(
                            onPressed: () => _recusarConvite(convite),
                            text: 'Recusar',
                            color: Colors.red,
                            width: 80,
                            height: 32,
                            fontSize: 12,
                          ),
                          SizedBox(width: 8),
                          _GlassButton(
                            onPressed: () => _aceitarConvite(convite),
                            text: 'Aceitar',
                            color: Colors.green,
                            width: 80,
                            height: 32,
                            fontSize: 12,
                          ),
                        ],
                      )
                    else if (convite['status'] == 1 && !expirou)
                      IconButton(
                        onPressed: () => _removerAcessoRecebido(convite),
                        icon: Icon(Icons.delete, color: Colors.red, size: 24),
                        tooltip: 'Remover acesso',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _getStatusConvite(int status, bool expirou) {
    if (expirou) {
      return {'texto': 'Expirado', 'color': Colors.orange};
    }

    switch (status) {
      case 0:
        return {'texto': 'Pendente', 'color': Colors.yellow};
      case 1:
        return {'texto': 'Aceito', 'color': Colors.green};
      case 2:
        return {'texto': 'Recusado', 'color': Colors.red};
      default:
        return {'texto': 'Desconhecido', 'color': Colors.grey};
    }
  }

  String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year} '
        '${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _revogarConvite(Map<String, dynamic> convite) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.blueGrey.shade800,
          title: Text('Revogar Convite', style: TextStyle(color: Colors.white)),
          content: Text(
            'Tem certeza que deseja revogar o convite?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancelar', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Revogar', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirma == true) {
      try {
        final backendToken = await LocalService.getBackendToken();
        if (backendToken == null) {
          _mostrarErro('Erro de autenticação');
          return;
        }

        final response = await http.post(
          Uri.parse(
            '${LocalService.backendUrl}/cancel_invite/${convite['id']}',
          ),
          headers: {'Authorization': 'Bearer $backendToken'},
        );

        if (response.statusCode == 200) {
          // Delete from Firestore
          final querySnapshot = await FirebaseFirestore.instance
              .collection('convites')
              .where('id', isEqualTo: convite['id'])
              .get();
          if (querySnapshot.docs.isNotEmpty) {
            await querySnapshot.docs.first.reference.delete();
          }

          _mostrarSucesso('Convite revogado com sucesso');
          await _carregarDados();
        } else {
          _mostrarErro('Erro ao revogar convite: ${response.statusCode}');
        }
      } catch (e) {
        _mostrarErro('Erro ao revogar convite: $e');
      }
    }
  }

  Future<void> _editarDataExpiracao(Map<String, dynamic> convite) async {
    String duracaoSelecionada = '1_semana';

    final novaData = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: EdgeInsets.all(24),
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
                        Text(
                          'Alterar Expiração',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Convite para: ${convite['destinatario_nome']}',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: duracaoSelecionada,
                          style: TextStyle(color: Colors.white),
                          dropdownColor: Colors.blueGrey.shade700,
                          decoration: InputDecoration(
                            labelText: 'Nova duração',
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white70),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.blueAccent),
                            ),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: '2_dias',
                              child: Text(
                                '2 Dias',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            DropdownMenuItem(
                              value: '1_semana',
                              child: Text(
                                '1 Semana',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            DropdownMenuItem(
                              value: '2_semanas',
                              child: Text(
                                '2 Semanas',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            DropdownMenuItem(
                              value: '1_mes',
                              child: Text(
                                '1 Mês',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'permanente',
                              child: Text(
                                'Permanente',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              duracaoSelecionada = value!;
                            });
                          },
                        ),
                        SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _GlassButton(
                              onPressed: () => Navigator.of(context).pop(),
                              text: 'Cancelar',
                              color: Colors.grey,
                              width: 80,
                              height: 36,
                            ),
                            SizedBox(width: 12),
                            _GlassButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(duracaoSelecionada),
                              text: 'Alterar',
                              color: Colors.blueAccent,
                              width: 80,
                              height: 36,
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

    if (novaData != null) {
      try {
        final backendToken = await LocalService.getBackendToken();
        if (backendToken == null) {
          _mostrarErro('Erro de autenticação');
          return;
        }

        final response = await http.post(
          Uri.parse(
            '${LocalService.backendUrl}/update_invite/${convite['id']}',
          ),
          headers: {
            'Authorization': 'Bearer $backendToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'expiry_duration': novaData}),
        );

        if (response.statusCode == 200) {
          _mostrarSucesso('Data de expiração alterada com sucesso');
          await _carregarDados();
        } else {
          _mostrarErro('Erro ao alterar expiração: ${response.statusCode}');
        }
      } catch (e) {
        _mostrarErro('Erro ao alterar expiração: $e');
      }
    }
  }

  Future<void> _aceitarConvite(Map<String, dynamic> convite) async {
    try {
      final backendToken = await LocalService.getBackendToken();
      if (backendToken == null) {
        _mostrarErro('Erro de autenticação');
        return;
      }

      final response = await http.post(
        Uri.parse('${LocalService.backendUrl}/accept_invite/${convite['id']}'),
        headers: {'Authorization': 'Bearer $backendToken'},
      );

      if (response.statusCode == 200) {
        // Update Firestore status to accepted
        final querySnapshot = await FirebaseFirestore.instance
            .collection('convites')
            .where('id', isEqualTo: convite['id'])
            .get();
        if (querySnapshot.docs.isNotEmpty) {
          await querySnapshot.docs.first.reference.update({'status': 1});
        }

        _mostrarSucesso('Convite aceito! Você agora tem acesso à fechadura.');
        await _carregarDados();
      } else {
        _mostrarErro('Erro ao aceitar convite: ${response.statusCode}');
      }
    } catch (e) {
      _mostrarErro('Erro ao aceitar convite: $e');
    }
  }

  Future<void> _recusarConvite(Map<String, dynamic> convite) async {
    try {
      final backendToken = await LocalService.getBackendToken();
      if (backendToken == null) {
        _mostrarErro('Erro de autenticação');
        return;
      }

      final response = await http.post(
        Uri.parse('${LocalService.backendUrl}/reject_invite/${convite['id']}'),
        headers: {'Authorization': 'Bearer $backendToken'},
      );

      if (response.statusCode == 200) {
        // Delete from Firestore
        final querySnapshot = await FirebaseFirestore.instance
            .collection('convites')
            .where('id', isEqualTo: convite['id'])
            .get();
        if (querySnapshot.docs.isNotEmpty) {
          await querySnapshot.docs.first.reference.delete();
        }

        _mostrarSucesso('Convite recusado');
        await _carregarDados();
      } else {
        _mostrarErro('Erro ao recusar convite: ${response.statusCode}');
      }
    } catch (e) {
      _mostrarErro('Erro ao recusar convite: $e');
    }
  }

  Future<void> _removerAcessoRecebido(Map<String, dynamic> convite) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: EdgeInsets.all(24),
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
                    Text(
                      'Remover Acesso',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Tem certeza que deseja remover o acesso à fechadura "${convite['fechadura_nome']}"?',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _GlassButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          text: 'Cancelar',
                          color: Colors.grey,
                          width: 80,
                          height: 36,
                        ),
                        SizedBox(width: 12),
                        _GlassButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          text: 'Remover',
                          color: Colors.red,
                          width: 80,
                          height: 36,
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

    if (confirma == true) {
      try {
        final backendToken = await LocalService.getBackendToken();
        if (backendToken == null) {
          _mostrarErro('Erro de autenticação');
          return;
        }

        final response = await http.post(
          Uri.parse(
            '${LocalService.backendUrl}/reject_invite/${convite['id']}',
          ),
          headers: {'Authorization': 'Bearer $backendToken'},
        );

        if (response.statusCode == 200) {
          // Delete from Firestore
          final querySnapshot = await FirebaseFirestore.instance
              .collection('convites')
              .where('id', isEqualTo: convite['id'])
              .get();
          if (querySnapshot.docs.isNotEmpty) {
            await querySnapshot.docs.first.reference.delete();
          }

          _mostrarSucesso('Acesso removido com sucesso');
          await _carregarDados();
        } else {
          _mostrarErro('Erro ao remover acesso: ${response.statusCode}');
        }
      } catch (e) {
        _mostrarErro('Erro ao remover acesso: $e');
      }
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
        return dataBase.add(Duration(days: 36500));
      default:
        return dataBase.add(Duration(days: 7));
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
}

class _GlassButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color color;
  final double width;
  final double height;
  final double fontSize;

  const _GlassButton({
    required this.text,
    required this.onPressed,
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
            onTap: onPressed,
            child: Center(
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.white,
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
