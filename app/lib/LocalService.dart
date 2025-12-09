import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'database.dart';

class LocalService {
  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUserId = 'user_id';

  static final _secureStorage = FlutterSecureStorage();

  // ==================== LOGIN ====================
  static Future<Map<String, dynamic>> login(String email, String senha) async {
    try {
      // Validar credenciais no banco
      final usuario = await DB.instance.buscarUsuarioPorEmailESenha(
        email,
        senha,
      );

      if (usuario == null) {
        return {'success': false, 'message': 'Email ou senha incorretos'};
      }

      // Criar sessão (gerar tokens)
      final tokens = await DB.instance.criarSessao(usuario['id'] as int);

      // Salvar tokens de forma segura
      await _salvarTokens(
        accessToken: tokens['access_token']!,
        refreshToken: tokens['refresh_token']!,
        userId: usuario['id'].toString(),
      );

      return {'success': true, 'user': usuario, 'tokens': tokens};
    } catch (e) {
      return {'success': false, 'message': 'Erro ao fazer login: $e'};
    }
  }

  //================== VALIDAR CONTATO =====================

  static Future<Map<String, dynamic>> validarContato(String contato) async {
    try {
      final usuario = await DB.instance.buscarUsuarioPorEmailOuTelefone(
        contato,
      );

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
    final userId = await getUserId();
    if (userId == null) return null;

    return await DB.instance.buscarUsuarioPorId(userId);
  }

  // ==================== LOGOUT ====================
  static Future<void> logout() async {
    try {
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
