import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:io';
import 'LocalService.dart';
import 'PaginaLogin.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:record/record.dart';

class PaginaConta extends StatefulWidget {
  const PaginaConta({super.key});

  @override
  State<PaginaConta> createState() => _PaginaContaState();
}

class _PaginaContaState extends State<PaginaConta> {
  bool _isLoading = true;
  Map<String, dynamic>? usuario;
  bool _hasVoiceEmbeddings = false;
  bool _isRecording = false;
  final AudioRecorder _audioRecorder = AudioRecorder();

  @override
  void initState() {
    super.initState();
    _carregarUsuario();
    _checkVoiceStatus();
  }

  Future<void> _checkVoiceStatus() async {
    try {
      print('DEBUG: Checking voice status...');
      final hasVoice = await LocalService.getVoiceStatus();
      print('DEBUG: Voice status result: $hasVoice');
      setState(() {
        _hasVoiceEmbeddings = hasVoice;
      });
    } catch (e) {
      print('Erro ao verificar status de voz: $e');
      setState(() {
        _hasVoiceEmbeddings = false; // Default to false on error
      });
    }
  }

  Future<void> _carregarUsuario() async {
    setState(() => _isLoading = true);

    try {
      final user = await LocalService.getUsuarioLogado();
      setState(() {
        usuario = user;
        _isLoading = false;
      });
    } catch (e) {
      print('Erro ao carregar usuário: $e');
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
          title: Text('Minha Conta', style: TextStyle(color: Colors.white)),
          iconTheme: IconThemeData(color: Colors.white, size: 30.0),
          centerTitle: true,
          backgroundColor: Colors.transparent,
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: Colors.blueAccent))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildInfoCard(),
                    SizedBox(height: 16),
                    _buildActionsCard(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return ClipRRect(
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
            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 60, color: Colors.black),
              ),
              SizedBox(height: 24),

              _buildInfoRow(
                icon: Icons.badge,
                label: 'ID',
                value: usuario?['id']?.toString() ?? 'N/A',
              ),

              Divider(color: Colors.white.withOpacity(0.2), height: 32),

              _buildInfoRow(
                icon: Icons.person_outline,
                label: 'Nome Completo',
                value: usuario?['nome'] ?? 'N/A',
              ),

              Divider(color: Colors.white.withOpacity(0.2), height: 32),

              _buildInfoRow(
                icon: Icons.email_outlined,
                label: 'Email',
                value: usuario?['email'] ?? 'N/A',
              ),

              Divider(color: Colors.white.withOpacity(0.2), height: 32),

              _buildInfoRow(
                icon: Icons.phone_outlined,
                label: 'Telefone',
                value: usuario?['telefone'] ?? 'Não cadastrado',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 24),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionsCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.all(16),
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
            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ações da Conta',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 16),

              _ActionButton(
                icon: Icons.phone_android,
                label: 'Alterar Telefone',
                color: Colors.blueAccent,
                onPressed: _mostrarDialogoAlterarTelefone,
              ),

              SizedBox(height: 12),

              _ActionButton(
                icon: Icons.lock_reset,
                label: 'Redefinir Senha',
                color: Colors.orange,
                onPressed: _mostrarDialogoRedefinirSenha,
              ),

              SizedBox(height: 12),

              _ActionButton(
                icon: Icons.mic,
                label: _hasVoiceEmbeddings ? 'Gerenciar Voz' : 'Registrar Voz',
                color: Colors.green,
                onPressed: _mostrarDialogoGerenciarVoz,
              ),

              SizedBox(height: 12),

              _ActionButton(
                icon: Icons.delete_forever,
                label: 'Deletar Conta',
                color: Colors.red,
                onPressed: _mostrarDialogoDeletarConta,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarDialogoAlterarTelefone() {
    final telefoneController = TextEditingController(
      text: usuario?['telefone'] ?? '',
    );

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: _GlassDialog(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Título
                  Row(
                    children: [
                      Icon(Icons.phone_android, color: Colors.blueAccent),
                      SizedBox(width: 8),
                      Text(
                        'Alterar Telefone',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 24),

                  // Campo de texto
                  TextField(
                    controller: telefoneController,
                    style: TextStyle(color: Colors.white),
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Novo Telefone',
                      labelStyle: TextStyle(color: Colors.white70),
                      hintText: '(00) 00000-0000',
                      hintStyle: TextStyle(color: Colors.white54),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white54),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blueAccent),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.phone, color: Colors.white70),
                    ),
                  ),
                  SizedBox(height: 24),

                  // Botões
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _GlassDialogButton(
                        onPressed: () => Navigator.of(context).pop(),
                        text: 'Cancelar',
                        color: Colors.red,
                      ),

                      SizedBox(width: 12),

                      _GlassDialogButton(
                        onPressed: () async {
                          final novoTelefone = telefoneController.text.trim();
                          if (novoTelefone.isEmpty) {
                            _mostrarErro('Digite um telefone válido');
                            return;
                          }

                          try {
                            // Update Firebase Firestore
                            await FirebaseFirestore.instance
                                .collection('usuarios')
                                .doc(FirebaseAuth.instance.currentUser!.uid)
                                .update({'telefone': novoTelefone});

                            // Update backend
                            final backendSuccess =
                                await LocalService.updatePhone(novoTelefone);
                            if (!backendSuccess) {
                              _mostrarErro(
                                'Telefone atualizado no Firebase, mas falhou no backend',
                              );
                              return;
                            }

                            await _carregarUsuario();
                            Navigator.of(context).pop();
                            _mostrarSucesso('Telefone atualizado com sucesso!');
                          } catch (e) {
                            _mostrarErro('Erro ao atualizar telefone: $e');
                          }
                        },
                        text: 'Salvar',
                        color: Colors.blueAccent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _mostrarDialogoRedefinirSenha() {
    final senhaAtualController = TextEditingController();
    final novaSenhaController = TextEditingController();
    final confirmarSenhaController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: _GlassDialog(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_reset, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        'Redefinir Senha',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 24),

                  TextField(
                    controller: senhaAtualController,
                    obscureText: true,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Senha Atual',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white54),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.lock, color: Colors.white70),
                    ),
                  ),
                  SizedBox(height: 12),

                  TextField(
                    controller: novaSenhaController,
                    obscureText: true,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Nova Senha',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white54),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(
                        Icons.lock_outline,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  SizedBox(height: 12),

                  TextField(
                    controller: confirmarSenhaController,
                    obscureText: true,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Confirmar Nova Senha',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white54),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(
                        Icons.lock_outline,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _GlassDialogButton(
                        onPressed: () => Navigator.of(context).pop(),
                        text: 'Cancelar',
                        color: Colors.red,
                      ),

                      SizedBox(width: 12),

                      _GlassDialogButton(
                        onPressed: () async {
                          final senhaAtual = senhaAtualController.text;
                          final novaSenha = novaSenhaController.text;
                          final confirmarSenha = confirmarSenhaController.text;

                          if (senhaAtual.isEmpty ||
                              novaSenha.isEmpty ||
                              confirmarSenha.isEmpty) {
                            _mostrarErro('Preencha todos os campos');
                            return;
                          }

                          if (novaSenha != confirmarSenha) {
                            _mostrarErro('As senhas não coincidem');
                            return;
                          }

                          if (novaSenha.length < 6) {
                            _mostrarErro(
                              'A senha deve ter pelo menos 6 caracteres',
                            );
                            return;
                          }

                          try {
                            // Update Firebase Auth
                            await FirebaseAuth.instance.currentUser!
                                .updatePassword(novaSenha);

                            // Update backend
                            final backendSuccess =
                                await LocalService.updatePassword(novaSenha);
                            if (!backendSuccess) {
                              _mostrarErro(
                                'Senha atualizada no Firebase, mas falhou no backend',
                              );
                              return;
                            }

                            await _carregarUsuario();
                            Navigator.of(context).pop();
                            _mostrarSucesso('Senha redefinida com sucesso!');
                          } catch (e) {
                            _mostrarErro('Erro ao redefinir senha: $e');
                          }
                        },
                        text: 'Alterar',
                        color: Colors.orange,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _mostrarDialogoDeletarConta() {
    final senhaController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: _GlassDialog(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        'Deletar Conta',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),

                  Text(
                    'Esta ação é irreversível!\n\nTodas as suas fechaduras, logs e convites serão permanentemente deletados.',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20),

                  TextField(
                    controller: senhaController,
                    obscureText: true,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Digite sua senha para confirmar',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Colors.red.withOpacity(0.5),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.red),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(
                        Icons.lock,
                        color: Colors.red.withOpacity(0.7),
                      ),
                    ),
                  ),
                  SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _GlassDialogButton(
                        onPressed: () => Navigator.of(context).pop(),
                        text: 'Cancelar',
                        color: Colors.blueAccent,
                      ),

                      SizedBox(width: 12),

                      _GlassDialogButton(
                        onPressed: () async {
                          final senha = senhaController.text;

                          if (senha.isEmpty) {
                            _mostrarErro('Digite sua senha para confirmar');
                            return;
                          }

                          // Verify password against backend
                          final passwordValid =
                              await LocalService.verifyPassword(senha);
                          if (!passwordValid) {
                            _mostrarErro('Senha incorreta');
                            return;
                          }

                          try {
                            // Delete devices from Firestore
                            final fechadurasSnapshot = await FirebaseFirestore
                                .instance
                                .collection('fechaduras')
                                .doc(usuario!['id'])
                                .collection('devices')
                                .get();
                            for (final doc in fechadurasSnapshot.docs) {
                              await doc.reference.delete();
                            }

                            // Delete user from Firebase Auth and Firestore
                            await FirebaseFirestore.instance
                                .collection('usuarios')
                                .doc(usuario!['id'])
                                .delete();
                            await FirebaseAuth.instance.currentUser!.delete();

                            // Delete from backend
                            final backendSuccess =
                                await LocalService.deleteAccount();
                            if (!backendSuccess) {
                              _mostrarErro(
                                'Conta deletada do Firebase, mas falhou no backend',
                              );
                              return;
                            }

                            await LocalService.logout();

                            Navigator.of(context).pop();
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (context) => const LoginPage(),
                              ),
                              (route) => false,
                            );

                            _mostrarSucesso('Conta deletada com sucesso');
                          } catch (e) {
                            _mostrarErro('Erro ao deletar conta: $e');
                          }
                        },
                        text: 'Deletar Conta',
                        color: Colors.red,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _mostrarDialogoGerenciarVoz() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: _GlassDialog(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.mic, color: Colors.green),
                      SizedBox(width: 8),
                      Text(
                        _hasVoiceEmbeddings ? 'Gerenciar Voz' : 'Cadastrar Voz',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Text(
                    _hasVoiceEmbeddings
                        ? 'Você já possui uma amostra de voz cadastrada. Deseja cadastrar uma nova ou remover a atual?'
                        : 'Cadastre sua voz para desbloquear dispositivos por comando de voz. A gravação durará 10 segundos. Esteja em um ambiente completamente silencioso e fale clara e continuamente bem próximo ao microfone.',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 24),
                  if (_hasVoiceEmbeddings) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _GlassDialogButton(
                          onPressed: () => Navigator.of(context).pop(),
                          text: 'Cancelar',
                          color: Colors.grey,
                        ),
                        _GlassDialogButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await _deletarVoz();
                          },
                          text: 'Remover',
                          color: Colors.red,
                        ),
                        _GlassDialogButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await _registrarVoz();
                          },
                          text: 'Nova Amostra',
                          color: Colors.green,
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _GlassDialogButton(
                          onPressed: () => Navigator.of(context).pop(),
                          text: 'Cancelar',
                          color: Colors.red,
                        ),
                        SizedBox(width: 12),
                        _GlassDialogButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await _registrarVoz();
                          },
                          text: 'Registrar',
                          color: Colors.green,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _registrarVoz() async {
    try {
      // Request microphone permission
      if (!await _audioRecorder.hasPermission()) {
        _mostrarErro('Permissão de microfone necessária');
        return;
      }

      setState(() => _isRecording = true);

      // Start recording
      final tempDir = await Directory.systemTemp.createTemp();
      final tempPath = '${tempDir.path}/voice_record.wav';
      final path = await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: tempPath,
      );

      // Show recording dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: _GlassDialog(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic, color: Colors.red, size: 48),
                    SizedBox(height: 16),
                    Text(
                      'Gravando...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Fale claramente por 10 segundos',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      // Record for 10 seconds
      await Future.delayed(Duration(seconds: 10));

      // Stop recording
      final audioPath = await _audioRecorder.stop();
      setState(() => _isRecording = false);

      Navigator.of(context).pop(); // Close recording dialog

      if (audioPath != null) {
        // Read audio file
        final audioFile = File(audioPath);
        final audioData = await audioFile.readAsBytes();

        // Send to backend
        final success = await LocalService.registerVoice(audioData);

        // Clean up temp file first
        await audioFile.delete();

        if (success) {
          await _checkVoiceStatus();
          _mostrarSucesso('Voz registrada com sucesso!');
        } else {
          _mostrarErro('Erro ao registrar voz');
        }
      } else {
        _mostrarErro('Erro na gravação');
      }
    } catch (e) {
      setState(() => _isRecording = false);
      Navigator.of(context).pop(); // Close any open dialogs
      _mostrarErro('Erro ao registrar voz: $e');
    }
  }

  Future<void> _deletarVoz() async {
    try {
      final success = await LocalService.deleteVoice();
      if (success) {
        await _checkVoiceStatus();
        _mostrarSucesso('Voz removida com sucesso!');
      } else {
        _mostrarErro('Erro ao remover voz');
      }
    } catch (e) {
      _mostrarErro('Erro ao remover voz: $e');
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
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
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 24),
                  SizedBox(width: 16),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white70,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassDialog extends StatelessWidget {
  final Widget child;

  const _GlassDialog({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
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
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassDialogButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color color;

  const _GlassDialogButton({
    required this.text,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          decoration: BoxDecoration(
            color: color.withOpacity(0.13),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
          ),

          child: TextButton(
            onPressed: onPressed,
            child: Text(text, style: TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
