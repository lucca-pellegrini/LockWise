import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database.dart';
import 'dart:async';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  static SyncService get instance => _instance;

  SyncService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Connectivity _connectivity = Connectivity();

  bool _isSyncing = false;
  StreamSubscription? _connectivitySubscription;
  Timer? _periodicSyncTimer;

  // Iniciar sincronização automática
  Future<void> iniciarSincronizacaoAutomatica(int usuarioId) async {
    // Sincronizar ao detectar conexão com internet
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      result,
    ) {
      if (result.first != ConnectivityResult.none) {
        sincronizarTudo(usuarioId);
      }
    });

    // Sincronização periódica a cada 5 minutos
    _periodicSyncTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      sincronizarTudo(usuarioId);
    });

    // Sincronização inicial
    await sincronizarTudo(usuarioId);
  }

  // Parar sincronização automática
  void pararSincronizacaoAutomatica() {
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();
  }

  // Verificar se há conexão com internet
  Future<bool> temConexao() async {
    final result = await _connectivity.checkConnectivity();
    return result.first != ConnectivityResult.none;
  }

  // Sincronizar tudo
  Future<void> sincronizarTudo(int usuarioId) async {
    if (_isSyncing) return; // Evitar sincronizações simultâneas

    if (!await temConexao()) {
      print('Sem conexão com internet. Sincronização adiada.');
      return;
    }

    _isSyncing = true;

    try {
      await sincronizarUsuario(usuarioId);
      await sincronizarFechaduras(usuarioId);
      await sincronizarConvites(usuarioId);
      await sincronizarLogs(usuarioId);

      print('Sincronização completa realizada com sucesso!');
    } catch (e) {
      print('Erro durante sincronização: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // ==================== SINCRONIZAÇÃO DE USUÁRIOS ====================

  Future<void> sincronizarUsuario(int usuarioId) async {
    try {
      // 1. Buscar usuário local
      final usuarioLocal = await DB.instance.buscarUsuarioPorId(usuarioId);

      if (usuarioLocal == null) return;

      final userRef = _firestore
          .collection('usuarios')
          .doc(usuarioId.toString());

      // 2. Buscar usuário no Firebase
      final userDoc = await userRef.get();

      if (!userDoc.exists) {
        // Usuário não existe no Firebase, criar
        await userRef.set({
          'id': usuarioLocal['id'],
          'nome': usuarioLocal['nome'],
          'email': usuarioLocal['email'],
          'telefone': usuarioLocal['telefone'],
          'senha': usuarioLocal['senha'], // Considere criptografar melhor
          'updated_at': FieldValue.serverTimestamp(),
        });
        print('Usuário criado no Firebase');
      } else {
        // Atualizar Firebase com dados locais
        await userRef.update({
          'nome': usuarioLocal['nome'],
          'email': usuarioLocal['email'],
          'telefone': usuarioLocal['telefone'],
          'senha': usuarioLocal['senha'],
          'updated_at': FieldValue.serverTimestamp(),
        });
        print('Usuário atualizado no Firebase');
      }
    } catch (e) {
      print('Erro ao sincronizar usuário: $e');
    }
  }

  // ==================== SINCRONIZAÇÃO DE FECHADURAS ====================

  Future<void> sincronizarFechaduras(int usuarioId) async {
    try {
      // 1. Buscar fechaduras locais
      final fechadurasLocais = await DB.instance.listarFechadurasDoUsuario(
        usuarioId,
      );

      // 2. Buscar fechaduras do Firebase
      final fechadurasSnapshot = await _firestore
          .collection('fechaduras')
          .where('usuario_id', isEqualTo: usuarioId)
          .get();

      // 3. Sincronizar do local para Firebase
      for (final fechaduraLocal in fechadurasLocais) {
        await _sincronizarFechadura(fechaduraLocal);
      }

      // 4. Sincronizar do Firebase para local (fechaduras que não existem localmente)
      for (final doc in fechadurasSnapshot.docs) {
        final firebaseData = doc.data();
        final fechaduraId = int.parse(doc.id);

        final existe = fechadurasLocais.any((f) => f['id'] == fechaduraId);

        if (!existe) {
          // Fechadura existe no Firebase mas não localmente, criar local
          await DB.instance.inserirFechadura({
            'id': fechaduraId,
            'nome': firebaseData['nome'],
            'usuario_id': firebaseData['usuario_id'],
            'icone_code_point': firebaseData['icone_code_point'],
            'notificacoes': firebaseData['notificacoes'] ?? 1,
            'acesso_remoto': firebaseData['acesso_remoto'] ?? 1,
            'aberto': firebaseData['aberto'] ?? 1,
          });
          print('Fechadura ${firebaseData['nome']} adicionada localmente');
        }
      }
    } catch (e) {
      print('Erro ao sincronizar fechaduras: $e');
    }
  }

  Future<void> _sincronizarFechadura(
    Map<String, dynamic> fechaduraLocal,
  ) async {
    try {
      final fechaduraRef = _firestore
          .collection('fechaduras')
          .doc(fechaduraLocal['id'].toString());
      final fechaduraDoc = await fechaduraRef.get();

      if (!fechaduraDoc.exists) {
        // Criar no Firebase
        await fechaduraRef.set({
          'id': fechaduraLocal['id'],
          'nome': fechaduraLocal['nome'],
          'usuario_id': fechaduraLocal['usuario_id'],
          'icone_code_point': fechaduraLocal['icone_code_point'],
          'notificacoes': fechaduraLocal['notificacoes'] ?? 1,
          'acesso_remoto': fechaduraLocal['acesso_remoto'] ?? 1,
          'aberto': fechaduraLocal['aberto'] ?? 1,
          'updated_at': FieldValue.serverTimestamp(),
        });
        print('Fechadura criada no Firebase');
      } else {
        // Atualizar no Firebase
        await fechaduraRef.update({
          'nome': fechaduraLocal['nome'],
          'icone_code_point': fechaduraLocal['icone_code_point'],
          'notificacoes': fechaduraLocal['notificacoes'] ?? 1,
          'acesso_remoto': fechaduraLocal['acesso_remoto'] ?? 1,
          'aberto': fechaduraLocal['aberto'] ?? 1,
          'updated_at': FieldValue.serverTimestamp(),
        });
        print('Fechadura atualizada no Firebase');
      }
    } catch (e) {
      print('Erro ao sincronizar fechadura: $e');
    }
  }

  // ==================== SINCRONIZAÇÃO DE CONVITES ====================

  Future<void> sincronizarConvites(int usuarioId) async {
    try {
      // Convites enviados
      final convitesEnviados = await DB.instance.listarConvitesDoRemetente(
        usuarioId,
      );
      for (final convite in convitesEnviados) {
        await _sincronizarConvite(convite);
      }

      // Convites recebidos
      final convitesRecebidos = await DB.instance.listarConvitesDoDestinatario(
        usuarioId,
      );
      for (final convite in convitesRecebidos) {
        await _sincronizarConvite(convite);
      }

      // Buscar convites do Firebase que não existem localmente
      final convitesFirebase = await _firestore
          .collection('convites')
          .where('destinatario_id', isEqualTo: usuarioId)
          .get();

      for (final doc in convitesFirebase.docs) {
        final firebaseData = doc.data();
        final conviteId = int.parse(doc.id);

        final existe = await DB.instance.buscarConvitePorId(conviteId);

        if (existe == null) {
          // Criar convite localmente
          await DB.instance.inserirConvite({
            'id': conviteId,
            'fechadura_id': firebaseData['fechadura_id'],
            'remetente_id': firebaseData['remetente_id'],
            'destinatario_id': firebaseData['destinatario_id'],
            'data_convite': firebaseData['data_convite'],
            'data_expiracao': firebaseData['data_expiracao'],
            'status': firebaseData['status'],
            'permissoes_admin': firebaseData['permissoes_admin'] ?? 0,
          });
          print('Convite adicionado localmente');
        }
      }
    } catch (e) {
      print('Erro ao sincronizar convites: $e');
    }
  }

  Future<void> _sincronizarConvite(Map<String, dynamic> conviteLocal) async {
    try {
      final conviteRef = _firestore
          .collection('convites')
          .doc(conviteLocal['id'].toString());
      final conviteDoc = await conviteRef.get();

      if (!conviteDoc.exists) {
        await conviteRef.set({
          'id': conviteLocal['id'],
          'fechadura_id': conviteLocal['fechadura_id'],
          'remetente_id': conviteLocal['remetente_id'],
          'destinatario_id': conviteLocal['destinatario_id'],
          'data_convite': conviteLocal['data_convite'],
          'data_expiracao': conviteLocal['data_expiracao'],
          'status': conviteLocal['status'],
          'permissoes_admin': conviteLocal['permissoes_admin'] ?? 0,
          'updated_at': FieldValue.serverTimestamp(),
        });
        print('Convite criado no Firebase');
      } else {
        await conviteRef.update({
          'status': conviteLocal['status'],
          'updated_at': FieldValue.serverTimestamp(),
        });
        print('Convite atualizado no Firebase');
      }
    } catch (e) {
      print('Erro ao sincronizar convite: $e');
    }
  }

  // ==================== SINCRONIZAÇÃO DE LOGS ====================

  Future<void> sincronizarLogs(int usuarioId) async {
    try {
      final logs = await DB.instance.listarLogsDoUsuario(usuarioId);

      for (final log in logs) {
        await _sincronizarLog(log);
      }
    } catch (e) {
      print('Erro ao sincronizar logs: $e');
    }
  }

  Future<void> _sincronizarLog(Map<String, dynamic> logLocal) async {
    try {
      final logRef = _firestore
          .collection('logs_acesso')
          .doc(logLocal['id'].toString());
      final logDoc = await logRef.get();

      if (!logDoc.exists) {
        await logRef.set({
          'id': logLocal['id'],
          'fechadura_id': logLocal['fechadura_id'],
          'usuario': logLocal['usuario'],
          'acao': logLocal['acao'],
          'data_hora': logLocal['data_hora'],
          'tipo_acesso': logLocal['tipo_acesso'],
        });
        print('Log criado no Firebase');
      }
    } catch (e) {
      print('Erro ao sincronizar log: $e');
    }
  }

  // ==================== OPERAÇÕES EM TEMPO REAL ====================

  // Criar fechadura com sincronização imediata
  Future<int> criarFechaduraSync(Map<String, dynamic> fechadura) async {
    // 1. Criar localmente
    final id = await DB.instance.inserirFechadura(fechadura);

    // 2. Tentar sincronizar com Firebase
    if (await temConexao()) {
      try {
        await _firestore.collection('fechaduras').doc(id.toString()).set({
          'id': id,
          'nome': fechadura['nome'],
          'usuario_id': fechadura['usuario_id'],
          'icone_code_point': fechadura['icone_code_point'],
          'notificacoes': fechadura['notificacoes'] ?? 1,
          'acesso_remoto': fechadura['acesso_remoto'] ?? 1,
          'aberto': fechadura['aberto'] ?? 1,
          'updated_at': FieldValue.serverTimestamp(),
        });
        print('Fechadura criada no Firebase');
      } catch (e) {
        print('Erro ao criar fechadura no Firebase: $e');
        // Continua mesmo se falhar no Firebase (será sincronizado depois)
      }
    }

    return id;
  }

  // Atualizar fechadura com sincronização imediata
  Future<void> atualizarFechaduraSync(
    int id,
    Map<String, dynamic> dados,
  ) async {
    // 1. Atualizar localmente
    await DB.instance.atualizarFechadura(id, dados);

    // 2. Tentar sincronizar com Firebase
    if (await temConexao()) {
      try {
        await _firestore.collection('fechaduras').doc(id.toString()).update({
          ...dados,
          'updated_at': FieldValue.serverTimestamp(),
        });
        print('Fechadura atualizada no Firebase');
      } catch (e) {
        print('Erro ao atualizar fechadura no Firebase: $e');
      }
    }
  }

  // Deletar fechadura com sincronização imediata
  Future<void> deletarFechaduraSync(int id) async {
    // 1. Deletar localmente
    await DB.instance.deletarFechadura(id);

    // 2. Tentar deletar do Firebase
    if (await temConexao()) {
      try {
        await _firestore.collection('fechaduras').doc(id.toString()).delete();
        print('Fechadura deletada do Firebase');
      } catch (e) {
        print('Erro ao deletar fechadura do Firebase: $e');
      }
    }
  }
}

