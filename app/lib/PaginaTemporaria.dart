import 'package:flutter/material.dart';
import 'models/LocalService.dart';
import 'dart:ui';
import 'PaginaDetalhe.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Temporaria extends StatefulWidget {
  const Temporaria({super.key});

  @override
  State<Temporaria> createState() => _TemporariaState();
}

class _TemporariaState extends State<Temporaria> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _fechadurasTemporarias = [];
  bool _isLoading = true;
  Map<String, dynamic>? _usuario;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carregarFechadurasTemporarias();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
        final usuarioId = _usuario!['id'] as String;

        // Buscar convites aceitos do usuário
        final querySnapshot = await FirebaseFirestore.instance
            .collection('convites')
            .where('destinatario_id', isEqualTo: usuarioId)
            .where('status', isEqualTo: 1)
            .get();
        final convitesAceitos = querySnapshot.docs
            .map((doc) => doc.data())
            .toList();
        final fechadurasComAcesso = <Map<String, dynamic>>[];

        for (final convite in convitesAceitos) {
          // Verificar se o convite foi aceito e não expirou
          if (convite['status'] == 1) {
            final dataExpiracao = DateTime.fromMillisecondsSinceEpoch(
              convite['data_expiracao'],
            );
            final agora = DateTime.now();

            if (agora.isBefore(dataExpiracao) ||
                convite['data_expiracao'] >
                    DateTime.now()
                        .add(Duration(days: 30000))
                        .millisecondsSinceEpoch) {
              // Buscar dados da fechadura
              final fechaduraDoc = await FirebaseFirestore.instance
                  .collection('fechaduras')
                  .doc(convite['fechadura_id'].toString())
                  .get();
              final fechadura = fechaduraDoc.exists
                  ? fechaduraDoc.data()
                  : null;

              if (fechadura != null) {
                // Buscar dados do proprietário
                final proprietarioDoc = await FirebaseFirestore.instance
                    .collection('usuarios')
                    .doc(convite['remetente_id'].toString())
                    .get();
                final proprietario = proprietarioDoc.exists
                    ? proprietarioDoc.data()
                    : null;

                fechadurasComAcesso.add({
                  'fechadura': fechadura,
                  'convite': convite,
                  'proprietario': proprietario,
                  'data_expiracao': dataExpiracao,
                });
              }
            }
          }
        }

        setState(() {
          _fechadurasTemporarias = fechadurasComAcesso;
          _isLoading = false;
        });
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
            ? _buildEmptyState()
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
        childAspectRatio: 0.85,
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
    final convite = item['convite'] as Map<String, dynamic>;
    final proprietario = item['proprietario'] as Map<String, dynamic>?;
    final dataExpiracao = item['data_expiracao'] as DateTime;

    final agora = DateTime.now();
    final diasRestantes = dataExpiracao.difference(agora).inDays;
    final horasRestantes = dataExpiracao.difference(agora).inHours;
    final isPermanente = diasRestantes > 30000;

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
                color: Colors.white.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        LockDetails(fechaduraId: fechadura['id']),
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

                    SizedBox(height: 8),

                    // Status de expiração
                    Row(
                      children: [
                        Icon(
                          isPermanente
                              ? Icons.all_inclusive
                              : Icons.access_time,
                          size: 16,
                          color: _getStatusColor(diasRestantes, isPermanente),
                        ),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
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
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    Spacer(),

                    // Badge de acesso temporário
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule, size: 12, color: Colors.orange),
                          SizedBox(width: 4),
                          Text(
                            'Acesso Temporário',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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

  String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
  }
}
