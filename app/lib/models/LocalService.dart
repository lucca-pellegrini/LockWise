import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'database.dart';

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
      // Buscar usuário no banco
      final usuario = await DB.instance.buscarUsuarioPorEmailESenha(
        email,
        senha,
      );

      if (usuario == null) {
        return {'success': false, 'message': 'E-mail ou senha incorretos'};
      }

      // Salvar preferência
      await setManterConectado(manterConectado);

      // Se escolheu manter conectado, salva os tokens
      if (manterConectado) {
        // Criar tokens de sessão
        final tokens = await DB.instance.criarSessao(usuario['id']);

        // Salvar tokens
        await _storage.write(
          key: _keyAccessToken,
          value: tokens['access_token'],
        );
        await _storage.write(
          key: _keyRefreshToken,
          value: tokens['refresh_token'],
        );
        await _storage.write(key: _keyUserId, value: usuario['id'].toString());
      } else {
        // Se não escolheu manter conectado, limpa qualquer token existente
        await logout();
      }

      return {'success': true, 'user': usuario};
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
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
    await _storage.write(key: _keyUserId, value: userId);
  }

  // ==================== OBTER ACCESS TOKEN ====================
  static Future<String?> getAccessToken() async {
    final accessToken = await _storage.read(key: _keyAccessToken);

    if (accessToken == null) return null;

    // Validar token no banco
    final usuarioId = await DB.instance.validarAccessToken(accessToken);

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

      // Renovar token no banco
      final novosTokens = await DB.instance.renovarToken(refreshToken);

      if (novosTokens == null) return false;

      // Obter userId do token antigo antes de substituir
      final userId = await _storage.read(key: _keyUserId);

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
      final usuarioId = await DB.instance.validarAccessToken(accessToken);

      if (usuarioId == null) {
        // Token inválido, tentar renovar
        final refreshToken = await _storage.read(key: _keyRefreshToken);

        if (refreshToken == null) {
          return false;
        }

        final novosTokens = await DB.instance.renovarToken(refreshToken);

        if (novosTokens == null) {
          await logout();
          return false;
        }

        // Salvar novos tokens
        await _storage.write(
          key: _keyAccessToken,
          value: novosTokens['access_token'],
        );
        await _storage.write(
          key: _keyRefreshToken,
          value: novosTokens['refresh_token'],
        );

        return true;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  // ==================== OBTER USER ID ====================
  static Future<int?> getUserId() async {
    try {
      final userIdString = await _storage.read(key: _keyUserId);
      return userIdString != null ? int.parse(userIdString) : null;
    } catch (e) {
      return null;
    }
  }

  // ==================== OBTER USUÁRIO LOGADO ====================
  static Future<Map<String, dynamic>?> getUsuarioLogado() async {
    try {
      final userId = await getUserId();
      if (userId == null) return null;

      return await DB.instance.buscarUsuarioPorId(userId);
    } catch (e) {
      return null;
    }
  }

  // ==================== LOGOUT ====================
  static Future<void> logout() async {
    try {
      final accessToken = await _storage.read(key: _keyAccessToken);

      if (accessToken != null) {
        await DB.instance.deletarSessao(accessToken);
      }

      // Limpar todos os dados armazenados
      await _storage.deleteAll();
    } catch (e) {
      print('Erro ao fazer logout: $e');
    }
  }
}

