import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LocalService {
  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUserId = 'user_id';

  static final _secureStorage = FlutterSecureStorage();

  // ==================== LOGIN ====================
  static Future<Map<String, dynamic>> login(
    String email,
    String senha, {
    bool manterConectado = false,
  }) async {
    try {
      // Fazer login no Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: senha);

      // Buscar dados do usuário no Firestore
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(userCredential.user!.uid)
          .get();

      if (!doc.exists) {
        return {
          'success': false,
          'message': 'Dados do usuário não encontrados',
        };
      }

      final usuario = doc.data()!;
      usuario['id'] = userCredential.user!.uid;

      // Criar sessão (gerar tokens) - ainda usando local para compatibilidade
      final tokens = await DB.instance.criarSessao(
        int.parse(userCredential.user!.uid),
      );

      // Salvar tokens de forma segura
      await _salvarTokens(
        accessToken: tokens['access_token']!,
        refreshToken: tokens['refresh_token']!,
        userId: usuario['id'],
      );

      return {'success': true, 'user': usuario, 'tokens': tokens};
    } on FirebaseAuthException catch (e) {
      String message = 'Erro ao fazer login';
      if (e.code == 'user-not-found') {
        message = 'Usuário não encontrado';
      } else if (e.code == 'wrong-password') {
        message = 'Senha incorreta';
      }
      return {'success': false, 'message': message};
    } catch (e) {
      return {'success': false, 'message': 'Erro ao fazer login: $e'};
    }
  }

  //================== VALIDAR CONTATO =====================

  static Future<Map<String, dynamic>> validarContato(String contato) async {
    try {
      // Verificar se é email ou telefone
      final querySnapshot = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('email', isEqualTo: contato)
          .get();

      Map<String, dynamic>? usuario;

      if (querySnapshot.docs.isNotEmpty) {
        usuario = querySnapshot.docs.first.data();
        usuario['id'] = querySnapshot.docs.first.id;
      } else {
        final querySnapshotTel = await FirebaseFirestore.instance
            .collection('usuarios')
            .where('telefone', isEqualTo: contato)
            .get();

        if (querySnapshotTel.docs.isNotEmpty) {
          usuario = querySnapshotTel.docs.first.data();
          usuario['id'] = querySnapshotTel.docs.first.id;
        }
      }

      if (usuario == null) {
        return {'success': false, 'message': 'Contato não encontrado'};
      }

      return {'success': true, 'user': usuario};
    } catch (e) {
      return {
        'success': false,
        'message': 'Erro ao tentar encontrar o usuario: $e',
      };
    }
  }

  // ==================== SALVAR TOKENS ====================
  static Future<void> _salvarTokens({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {
    await _secureStorage.write(key: _keyAccessToken, value: accessToken);
    await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
    await _secureStorage.write(key: _keyUserId, value: userId);
  }

  // ==================== OBTER ACCESS TOKEN ====================
  static Future<String?> getAccessToken() async {
    final accessToken = await _secureStorage.read(key: _keyAccessToken);

    if (accessToken == null) return null;

    // Validar token no banco
    final usuarioId = await DB.instance.validarAccessToken(accessToken);

    if (usuarioId == null) {
      // Token inválido ou expirado, tentar renovar
      final renovado = await _renovarToken();
      if (renovado) {
        return await _secureStorage.read(key: _keyAccessToken);
      }
      return null;
    }

    return accessToken;
  }

  // ==================== RENOVAR TOKEN ====================
  static Future<bool> _renovarToken() async {
    try {
      final refreshToken = await _secureStorage.read(key: _keyRefreshToken);

      if (refreshToken == null) return false;

      // Renovar token no banco
      final novosTokens = await DB.instance.renovarToken(refreshToken);

      if (novosTokens == null) return false;

      // Obter userId do token antigo antes de substituir
      final userId = await _secureStorage.read(key: _keyUserId);

      // Salvar novos tokens
      await _salvarTokens(
        accessToken: novosTokens['access_token']!,
        refreshToken: novosTokens['refresh_token']!,
        userId: userId ?? '0',
      );

      return true;
    } catch (e) {
      print('Erro ao renovar token: $e');
      return false;
    }
  }

  // ==================== VERIFICAR SE ESTÁ LOGADO ====================
  static Future<bool> estaLogado() async {
    final token = await getAccessToken();
    return token != null;
  }

  // ==================== OBTER USER ID ====================
  static Future<int?> getUserId() async {
    final userIdStr = await _secureStorage.read(key: _keyUserId);
    if (userIdStr == null) return null;
    return int.tryParse(userIdStr);
  }

  // ==================== OBTER USUÁRIO LOGADO ====================
  static Future<Map<String, dynamic>?> getUsuarioLogado() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .get();

    if (!doc.exists) return null;

    final usuario = doc.data()!;
    usuario['id'] = user.uid;

    return usuario;
  }

  // ==================== LOGOUT ====================
  static Future<void> logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      final accessToken = await _secureStorage.read(key: _keyAccessToken);

      // Deletar sessão do banco
      if (accessToken != null) {
        await DB.instance.deletarSessao(accessToken);
      }
    } catch (e) {
      print('Erro ao fazer logout: $e');
    } finally {
      // Limpar tokens do armazenamento seguro
      await _secureStorage.delete(key: _keyAccessToken);
      await _secureStorage.delete(key: _keyRefreshToken);
      await _secureStorage.delete(key: _keyUserId);
    }
  }
}
