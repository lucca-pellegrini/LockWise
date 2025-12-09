import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class DB {
  DB._();
  static final DB instance = DB._();
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    return await openDatabase(
      join(await getDatabasesPath(), 'fechadura.db'),

      version: 3,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Criar tabelas esta ordem (primeiro usuários, depois tokens, depois fechaduras, depois logs)
    await db.execute(_usuarios);
    await db.execute(_tokens);
    await db.execute(_fechaduras);
    await db.execute(_logAcesso);
    await db.execute(_convites);
    await db.execute(_administradoresFechaduras);
  }

  // Tabela de usuários
  String get _usuarios => '''
    CREATE TABLE usuarios (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT NOT NULL,
      email TEXT NOT NULL UNIQUE,
      telefone TEXT,
      senha TEXT NOT NULL,
      updated_at INTEGER DEFAULT 0
    )
  ''';

  // Tabela de Tokens de autenticação
  String get _tokens => '''
    CREATE TABLE IF NOT EXISTS tokens (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id INTEGER NOT NULL,
      token TEXT NOT NULL,
      refresh_token TEXT NOT NULL,
      data_criacao INTEGER NOT NULL,
      data_expiracao INTEGER NOT NULL,
      FOREIGN KEY (usuario_id) REFERENCES usuarios (id) ON DELETE CASCADE
    )
  ''';

  // Tabela de fechaduras (referencia o usuário)
  String get _fechaduras => '''
    CREATE TABLE fechaduras (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id INTEGER NOT NULL,
      nome TEXT NOT NULL,
      icone_code_point INTEGER NOT NULL,
      notificacoes INTEGER NOT NULL DEFAULT 1,
      acesso_remoto INTEGER NOT NULL DEFAULT 1,
      aberto INTEGER NOT NULL DEFAULT 1,
      updated_at INTEGER DEFAULT 0,
      FOREIGN KEY (usuario_id) REFERENCES usuarios (id) ON DELETE CASCADE
    )
  ''';

  // Tabela de log de acesso (referencia a fechadura)
  String get _logAcesso => '''
    CREATE TABLE log_acesso (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      fechadura_id INTEGER NOT NULL,
      usuario TEXT NOT NULL,
      acao TEXT NOT NULL,
      data_hora INTEGER NOT NULL,
      tipo_acesso TEXT NOT NULL,
      FOREIGN KEY (fechadura_id) REFERENCES fechaduras (id) ON DELETE CASCADE
    )
  ''';

  //Tabela de convites (referencia o usuário e a fechadura)
  String get _convites => '''
    CREATE TABLE convites (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      fechadura_id INTEGER NOT NULL,
      remetente_id INTEGER NOT NULL,
      destinatario_id INTEGER NOT NULL,
      data_convite INTEGER NOT NULL,
      data_expiracao INTEGER NOT NULL,
      status INTEGER NOT NULL,
      permissoes_admin INTEGER NOT NULL,
      FOREIGN KEY (fechadura_id) REFERENCES fechaduras (id) ON DELETE CASCADE,
      FOREIGN KEY (remetente_id) REFERENCES usuarios (id) ON DELETE CASCADE,
      FOREIGN KEY (destinatario_id) REFERENCES usuarios (id) ON DELETE CASCADE
    )
  ''';

  //Tabela de adminstradores de fechaduras (referencia o usuário e a fechadura)
  String get _administradoresFechaduras => '''
    CREATE TABLE administradores_fechaduras (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      fechadura_id INTEGER NOT NULL,
      usuario_id INTEGER NOT NULL,
      FOREIGN KEY (fechadura_id) REFERENCES fechaduras (id) ON DELETE CASCADE,
      FOREIGN KEY (usuario_id) REFERENCES usuarios (id) ON DELETE CASCADE
    )
  ''';

  // ==================== OPERAÇÕES COM USUÁRIOS ====================

  Future<int> inserirUsuario(Map<String, dynamic> usuario) async {
    final db = await database;
    return await db.insert('usuarios', usuario);
  }

  Future<Map<String, dynamic>?> buscarUsuarioPorEmail(String email) async {
    final db = await database;
    final result = await db.query(
      'usuarios',
      where: 'email = ?',
      whereArgs: [email],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<Map<String, dynamic>?> buscarUsuarioPorEmailOuTelefone(
    String contato,
  ) async {
    final db = await database;
    final result = await db.query(
      'usuarios',
      where: 'email = ? OR telefone = ?',
      whereArgs: [contato, contato],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<Map<String, dynamic>?> buscarUsuarioPorEmailESenha(
    String email,
    String senha,
  ) async {
    final db = await database;
    final result = await db.query(
      'usuarios',
      where: 'email = ? AND senha = ?',
      whereArgs: [email, senha],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<Map<String, dynamic>?> buscarUsuarioPorId(int id) async {
    final db = await database;
    final result = await db.query('usuarios', where: 'id = ?', whereArgs: [id]);
    return result.isNotEmpty ? result.first : null;
  }

  Future<List<Map<String, dynamic>>> listarTodosUsuarios() async {
    final db = await database;
    return await db.query('usuarios', orderBy: 'id DESC');
  }

  Future<int> atualizarUsuario(int id, Map<String, dynamic> usuario) async {
    final db = await database;
    return await db.update(
      'usuarios',
      usuario,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deletarUsuario(int id) async {
    final db = await database;
    return await db.delete('usuarios', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== OPERAÇÕES COM FECHADURAS ====================

  Future<int> inserirFechadura(Map<String, dynamic> fechadura) async {
    final db = await database;
    return await db.insert('fechaduras', fechadura);
  }

  Future<List<Map<String, dynamic>>> listarFechadurasDoUsuario(
    int usuarioId,
  ) async {
    final db = await database;
    return await db.query(
      'fechaduras',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
    );
  }

  Future<Map<String, dynamic>?> buscarFechadura(int id) async {
    final db = await database;
    final result = await db.query(
      'fechaduras',
      where: 'id = ?',
      whereArgs: [id],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> atualizarFechadura(int id, Map<String, dynamic> fechadura) async {
    final db = await database;
    return await db.update(
      'fechaduras',
      fechadura,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deletarFechadura(int id) async {
    final db = await database;
    return await db.delete('fechaduras', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== OPERAÇÕES COM LOG DE ACESSO ====================

  Future<int> inserirLogAcesso(Map<String, dynamic> log) async {
    final db = await database;
    return await db.insert('log_acesso', log);
  }

  Future<List<Map<String, dynamic>>> listarLogsDeAcesso(int fechaduraId) async {
    final db = await database;
    return await db.query(
      'log_acesso',
      where: 'fechadura_id = ?',
      whereArgs: [fechaduraId],
      orderBy: 'data_hora DESC',
    );
  }

  Future<List<Map<String, dynamic>>> listarTodosLogs() async {
    final db = await database;
    return await db.query('log_acesso', orderBy: 'data_hora DESC');
  }

  Future<List<Map<String, dynamic>>> listarLogsDoUsuario(int usuarioId) async {
    final db = await database;
    return await db.rawQuery(
      '''
    SELECT 
      log_acesso.*,
      fechaduras.nome as fechadura_nome
    FROM log_acesso
    INNER JOIN fechaduras ON log_acesso.fechadura_id = fechaduras.id
    WHERE fechaduras.usuario_id = ?
       OR fechaduras.id IN (
         SELECT c.fechadura_id 
         FROM convites c 
         WHERE c.destinatario_id = ? 
         AND c.status = 1
         AND c.data_expiracao > ?
       )
       OR fechaduras.id IN (
         SELECT af.fechadura_id 
         FROM administradores_fechaduras af 
         WHERE af.usuario_id = ?
       )
    ORDER BY log_acesso.data_hora DESC
  ''',
      [
        usuarioId, // Fechaduras próprias
        usuarioId, // Convites aceitos
        DateTime.now().millisecondsSinceEpoch, // Convites não expirados
        usuarioId, // Fechaduras onde é administrador
      ],
    );
  }

  Future<int> deletarLog(int id) async {
    final db = await database;
    return await db.delete('log_acesso', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deletarLogsDaFechadura(int fechaduraId) async {
    final db = await database;
    return await db.delete(
      'log_acesso',
      where: 'fechadura_id = ?',
      whereArgs: [fechaduraId],
    );
  }

  Future<int> deletarLogsDoUsuario(int usuarioId) async {
    final db = await database;
    return await db.delete(
      'log_acesso',
      where: 'fechadura_id IN (SELECT id FROM fechaduras WHERE usuario_id = ?)',
      whereArgs: [usuarioId],
    );
  }

  // ==================== OPERAÇÕES ADICIONAIS ====================

  // Limpar todas as tabelas (útil para testes)
  Future<void> limparTodasTabelas() async {
    final db = await database;
    await db.delete('log_acesso');
    await db.delete('fechaduras');
    await db.delete('usuarios');
  }

  // Fechar o banco de dados
  Future<void> fecharBanco() async {
    final db = await database;
    await db.close();
  }

  Future<int> atualizarSenha(String emailOuTelefone, String novaSenha) async {
    final db = await database;
    return await db.update(
      'usuarios',
      {'senha': novaSenha},
      where: 'email = ? OR telefone = ?',
      whereArgs: [emailOuTelefone, emailOuTelefone],
    );
  }

  // ==================== OPERAÇÕES COMO TOKENS ==================

  Future<Map<String, String>> criarSessao(int usuarioId) async {
    final db = await database;

    final accessToken = _gerarToken(usuarioId, 'access');
    final refreshToken = _gerarToken(usuarioId, 'refresh');

    final agora = DateTime.now().millisecondsSinceEpoch;
    final expiraEm = DateTime.now()
        .add(Duration(days: 30))
        .millisecondsSinceEpoch;

    await db.insert('tokens', {
      'usuario_id': usuarioId,
      'token': accessToken,
      'refresh_token': refreshToken,
      'data_criacao': agora,
      'data_expiracao': expiraEm,
    });

    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expires_in': '2592000',
    };
  }

  String _gerarToken(int usuarioId, String tipo) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch;
    final data = '$usuarioId-$tipo-$timestamp-$random';
    final bytes = utf8.encode(data);
    return sha256.convert(bytes).toString();
  }

  Future<int?> validarAccessToken(String accessToken) async {
    final db = await database;

    final result = await db.query(
      'tokens',
      where: 'token = ?',
      whereArgs: [accessToken],
    );

    if (result.isEmpty) return null;

    final token = result.first;
    final expiraEm = token['data_expiracao'] as int;
    final agora = DateTime.now().millisecondsSinceEpoch;

    if (agora > expiraEm) {
      await db.delete('tokens', where: 'id = ?', whereArgs: [token['id']]);
      return null;
    }

    return token['usuario_id'] as int;
  }

  Future<Map<String, String>?> renovarToken(String refreshToken) async {
    final db = await database;

    final result = await db.query(
      'tokens',
      where: 'refresh_token = ?',
      whereArgs: [refreshToken],
    );

    if (result.isEmpty) return null;

    final tokenAntigo = result.first;
    final usuarioId = tokenAntigo['usuario_id'] as int;

    await db.delete('tokens', where: 'id = ?', whereArgs: [tokenAntigo['id']]);

    return await criarSessao(usuarioId);
  }

  Future<void> deletarSessao(String accessToken) async {
    final db = await database;

    await db.delete('tokens', where: 'token = ?', whereArgs: [accessToken]);
  }

  Future<void> limparTokensExpirados() async {
    final db = await database;
    final agora = DateTime.now().millisecondsSinceEpoch;

    await db.delete('tokens', where: 'data_expiracao < ?', whereArgs: [agora]);
  }

  // ==================== OPERAÇÕES COM CONVITES ====================

  Future<int> inserirConvite(Map<String, dynamic> convite) async {
    final db = await database;
    return await db.insert('convites', convite);
  }

  Future<List<Map<String, dynamic>>> listarConvitesDoRemetente(
    int remetenteId,
  ) async {
    final db = await database;
    return await db.query(
      'convites',
      where: 'remetente_id = ?',
      whereArgs: [remetenteId],
    );
  }

  Future<List<Map<String, dynamic>>> listarConvitesDoDestinatario(
    int destinatarioId,
  ) async {
    final db = await database;
    return await db.query(
      'convites',
      where: 'destinatario_id = ?',
      whereArgs: [destinatarioId],
    );
  }

  Future<List<Map<String, dynamic>>> listarConvitesDaFechadura(
    int fechaduraId,
  ) async {
    final db = await database;
    return await db.query(
      'convites',
      where: 'fechadura_id = ?',
      whereArgs: [fechaduraId],
    );
  }

  Future<int> atualizarConvite(int id, Map<String, dynamic> convite) async {
    final db = await database;
    return await db.update(
      'convites',
      convite,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deletarConvite(int id) async {
    final db = await database;
    return await db.delete('convites', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deletarConvitesDaFechadura(int fechaduraId) async {
    final db = await database;
    return await db.delete(
      'convites',
      where: 'fechadura_id = ?',
      whereArgs: [fechaduraId],
    );
  }

  Future<int> deletarConvitesDoRemetente(int remetenteId) async {
    final db = await database;
    return await db.delete(
      'convites',
      where: 'remetente_id = ?',
      whereArgs: [remetenteId],
    );
  }

  Future<int> deletarConvitesDoDestinatario(int destinatarioId) async {
    final db = await database;
    return await db.delete(
      'convites',
      where: 'destinatario_id = ?',
      whereArgs: [destinatarioId],
    );
  }

  Future<Map<String, dynamic>?> buscarConvitePorId(int id) async {
    final db = await database;
    final results = await db.query(
      'convites',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  // =================== OPERAÇÕES COM ADMINISTRADORES ====================

  Future<int> inserirAdministradorFechadura(Map<String, dynamic> admin) async {
    final db = await DB.instance.database;
    return await db.insert('administradores_fechaduras', admin);
  }

  Future<int> deletarAdministradorFechadura(
    int fechaduraId,
    int usuarioId,
  ) async {
    final db = await DB.instance.database;
    return await db.delete(
      'administradores_fechaduras',
      where: 'fechadura_id = ? AND usuario_id = ?',
      whereArgs: [fechaduraId, usuarioId],
    );
  }

  Future<List<Map<String, dynamic>>> listarAdministradoresDaFechadura(
    int fechaduraId,
  ) async {
    final db = await DB.instance.database;
    return await db.query(
      'administradores_fechaduras',
      where: 'fechadura_id = ?',
      whereArgs: [fechaduraId],
    );
  }

  Future<List<Map<String, dynamic>>> listarFechadurasDoAdministradasPeloUsuario(
    int usuarioId,
  ) async {
    final db = await DB.instance.database;
    return await db.query(
      'administradores_fechaduras',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
    );
  }

  Future<bool> verificarSeUsuarioEAdministrador(
    int fechaduraId,
    int usuarioId,
  ) async {
    final db = await DB.instance.database;
    final result = await db.query(
      'administradores_fechaduras',
      where: 'fechadura_id = ? AND usuario_id = ?',
      whereArgs: [fechaduraId, usuarioId],
    );
    return result.isNotEmpty;
  }
}
