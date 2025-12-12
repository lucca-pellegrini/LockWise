import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

const String backendUrl = 'http://192.168.0.75:12223';

class LocalService {
  static const String _keyBackendToken = 'backend_token';
  static const String _keyUserId = 'user_id';
  static const String _keyManterConectado = 'manter_conectado';

  static final _storage = FlutterSecureStorage();

  static Future<bool> getManterConectado() async {
    final valor = await _storage.read(key: _keyManterConectado);
    return valor == null ? true : valor == 'true';
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

      // Call backend login
      final response = await http.post(
        Uri.parse('$backendUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'firebase_uid': userCredential.user!.uid,
          'password': senha,
        }),
      );

      if (response.statusCode != 200) {
        return {'success': false, 'message': 'Backend login failed'};
      }

      final backendToken = response.body
          .trim(); // Assume it returns the token as plain text

      // Salvar preferência
      await setManterConectado(manterConectado);

      // Se escolheu manter conectado, salva o token
      if (manterConectado) {
        await _storage.write(key: _keyBackendToken, value: backendToken);
        await _storage.write(key: _keyUserId, value: usuario['id']);
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

  // ==================== OBTER BACKEND TOKEN ====================
  static Future<String?> getBackendToken() async {
    return await _storage.read(key: _keyBackendToken);
  }

  // ==================== VERIFICAR SE ESTÁ LOGADO ====================
  static Future<bool> estaLogado() async {
    try {
      // Verificar se tem preferência de manter conectado
      final manterConectado = await getManterConectado();
      if (!manterConectado) {
        return false;
      }

      final backendToken = await _storage.read(key: _keyBackendToken);

      return backendToken != null;
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
      // Call backend logout if token exists
      final token = await _storage.read(key: _keyBackendToken);
      if (token != null) {
        await http.post(
          Uri.parse('$backendUrl/logout'),
          headers: {'Authorization': 'Bearer $token'},
        );
      }

      await FirebaseAuth.instance.signOut();

      // Limpar todos os dados armazenados
      await _storage.deleteAll();
    } catch (e) {
      print('Erro ao fazer logout: $e');
    }
  }

  // ==================== UPDATE PHONE ====================
  static Future<bool> updatePhone(String phoneNumber) async {
    try {
      final token = await _storage.read(key: _keyBackendToken);
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('$backendUrl/update_phone'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'phone_number': phoneNumber}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao atualizar telefone: $e');
      return false;
    }
  }

  // ==================== UPDATE PASSWORD ====================
  static Future<bool> updatePassword(String newPassword) async {
    try {
      final token = await _storage.read(key: _keyBackendToken);
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('$backendUrl/update_password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'password': newPassword}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao atualizar senha: $e');
      return false;
    }
  }

  // ==================== DELETE ACCOUNT ====================
  static Future<bool> deleteAccount() async {
    try {
      final token = await _storage.read(key: _keyBackendToken);
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('$backendUrl/delete_account'),
        headers: {'Authorization': 'Bearer $token'},
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao deletar conta: $e');
      return false;
    }
  }

  // ==================== VERIFY PASSWORD ====================
  static Future<bool> verifyPassword(String password) async {
    try {
      final token = await _storage.read(key: _keyBackendToken);
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('$backendUrl/verify_password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'password': password}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao verificar senha: $e');
      return false;
    }
  }
}
