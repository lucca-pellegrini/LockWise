import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LocalService {
  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUserId = 'user_id';
  static const String _keyManterConectado = 'manter_conectado';

  static final _storage = FlutterSecureStorage();

  static Future<bool> getManterConectado() async {
    final valor = await _storage.read(key: _keyManterConectado);
    return valor == 'true';
  }

  static Future<void> setManterConectado(bool valor) async {
    await _storage.write(key: _keyManterConectado, value: valor.toString());
  }

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

      // Salvar preferência
      await setManterConectado(manterConectado);

      // Se escolheu manter conectado, salva os tokens
      if (manterConectado) {
        // Criar tokens de sessão
        final tokens = await _criarSessao(usuario['id']);

        // Salvar tokens
        await _salvarTokens(
          accessToken: tokens['access_token']!,
          refreshToken: tokens['refresh_token']!,
          userId: usuario['id'],
        );
      } else {
        // Se não escolheu manter conectado, limpa qualquer token existente
        await logout();
      }

      return {'success': true, 'user': usuario};
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
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
    await _storage.write(key: _keyUserId, value: userId);
  }

  // ==================== OBTER ACCESS TOKEN ====================
  static Future<String?> getAccessToken() async {
    final accessToken = await _storage.read(key: _keyAccessToken);

    if (accessToken == null) return null;

    // Validar token
    final usuarioId = await validarAccessToken(accessToken);

    if (usuarioId == null) {
      // Token inválido ou expirado, tentar renovar
      final renovado = await _renovarToken();
      if (renovado) {
        return await _storage.read(key: _keyAccessToken);
      }
      return null;
    }

    return accessToken;
  }

  // ==================== RENOVAR TOKEN ====================
  static Future<bool> _renovarToken() async {
    try {
      final refreshToken = await _storage.read(key: _keyRefreshToken);

      if (refreshToken == null) return false;

      // Obter userId
      final userId = await _storage.read(key: _keyUserId);

      if (userId == null) return false;

      // Criar novos tokens
      final novosTokens = await _criarSessao(userId);

      // Salvar novos tokens
      await _salvarTokens(
        accessToken: novosTokens['access_token']!,
        refreshToken: novosTokens['refresh_token']!,
        userId: userId,
      );

      return true;
    } catch (e) {
      print('Erro ao renovar token: $e');
      return false;
    }
  }

  // ==================== VERIFICAR SE ESTÁ LOGADO ====================
  static Future<bool> estaLogado() async {
    try {
      // Verificar se tem preferência de manter conectado
      final manterConectado = await getManterConectado();
      if (!manterConectado) {
        return false;
      }

      final accessToken = await _storage.read(key: _keyAccessToken);

      if (accessToken == null) {
        return false;
      }

      // Validar o token
      final usuarioId = await validarAccessToken(accessToken);

      if (usuarioId == null) {
        // Token inválido, tentar renovar
        final refreshToken = await _storage.read(key: _keyRefreshToken);

        if (refreshToken == null) {
          return false;
        }

        final novosTokens = await _renovarToken();

        if (novosTokens == null) {
          await logout();
          return false;
        }

        return true;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  // ==================== OBTER USER ID ====================
  static Future<String?> getUserId() async {
    final userIdString = await _storage.read(key: _keyUserId);
    return userIdString;
  }

  // ==================== OBTER USUÁRIO LOGADO ====================
  static Future<Map<String, dynamic>?> getUsuarioLogado() async {
    try {
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
    } catch (e) {
      return null;
    }
  }

  // ==================== LOGOUT ====================
  static Future<void> logout() async {
    try {
      await FirebaseAuth.instance.signOut();

      // Limpar todos os dados armazenados
      await _storage.deleteAll();
    } catch (e) {
      print('Erro ao fazer logout: $e');
    }
  }

  // ==================== CRIAR SESSAO ====================
  static Future<Map<String, String>> _criarSessao(String usuarioId) async {
    final accessToken = _gerarToken(usuarioId, 'access');
    final refreshToken = _gerarToken(usuarioId, 'refresh');

    final agora = DateTime.now().millisecondsSinceEpoch;
    final expiraEm = DateTime.now()
        .add(Duration(days: 30))
        .millisecondsSinceEpoch;

    // Salvar expiração
    await _storage.write(
      key: '${_keyAccessToken}_exp',
      value: expiraEm.toString(),
    );
    await _storage.write(
      key: '${_keyRefreshToken}_exp',
      value: expiraEm.toString(),
    );

    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expires_in': '2592000',
    };
  }

  static String _gerarToken(String usuarioId, String tipo) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch;
    final data = '$usuarioId-$tipo-$timestamp-$random';
    return data.hashCode.toString();
  }

  static Future<String?> validarAccessToken(String accessToken) async {
    final expStr = await _storage.read(key: '${_keyAccessToken}_exp');
    if (expStr == null) return null;

    final expiraEm = int.tryParse(expStr);
    if (expiraEm == null) return null;

    final agora = DateTime.now().millisecondsSinceEpoch;
    if (agora > expiraEm) {
      await _deletarSessao(accessToken);
      return null;
    }

    final userId = await _storage.read(key: _keyUserId);
    return userId;
  }

  static Future<Map<String, String>?> renovarToken(String refreshToken) async {
    final userId = await _storage.read(key: _keyUserId);
    if (userId == null) return null;

    return await _criarSessao(userId);
  }

  static Future<void> _deletarSessao(String accessToken) async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: '${_keyAccessToken}_exp');
    await _storage.delete(key: '${_keyRefreshToken}_exp');
  }
}
