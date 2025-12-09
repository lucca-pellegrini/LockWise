import 'package:fechaduraflow/PaginaEsqueci.dart';
import 'package:flutter/material.dart';
import 'PaginaInicial.dart';
import 'PaginaCadastro.dart';
import 'models/database.dart';
import 'models/LocalService.dart';
import 'models/SyncService.dart';
import 'dart:ui';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _manterConectado = false;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _senhaController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _senhaFieldKey = GlobalKey<FormFieldState>();
  String? _erroSenha;
  bool _emailFocused = false;
  bool _senhaFocused = false;
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _senhaFocusNode = FocusNode();

  Widget _buildImage(String assetName, [double width = 350]) {
    return Image.asset('images/$assetName', width: width);
  }

  @override
  void initState() {
    super.initState();
    _carregarPreferencias();

    // Adicionar listeners para os focus nodes
    _emailFocusNode.addListener(() {
      setState(() {
        _emailFocused = _emailFocusNode.hasFocus;
      });
    });

    _senhaFocusNode.addListener(() {
      setState(() {
        _senhaFocused = _senhaFocusNode.hasFocus;
      });
    });
  }

  Future<void> _carregarPreferencias() async {
    // Carregar preferência de manter conectado
    final manterConectado = await LocalService.getManterConectado();
    setState(() {
      _manterConectado = manterConectado;
    });

    // Verificar login automático apenas se estava marcado para manter conectado
    if (_manterConectado) {
      await _verificarLoginAutomatico();
    }
  }

  Future<void> _verificarLoginAutomatico() async {
    final estaLogado = await LocalService.estaLogado();

    if (estaLogado && mounted) {
      // Obter userId do token
      final userId = await LocalService.getUserId();

      if (userId != null) {
        // Já está logado, ir direto para tela inicial

        SyncService.instance.sincronizarTudo(userId);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => Inicial(usuarioId: userId)),
        );
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    _emailFocusNode.dispose();
    _senhaFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bool tecladoAberto = media.viewInsets.bottom > 0;
    final bottomInset = media.viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('images/Fundo.jpg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.0),
              BlendMode.srcOver,
            ),
          ),
        ),

        child: Stack(
          children: [
            Column(
              children: [
                Spacer(flex: 1),
                Center(
                  child: Form(
                    key: _formKey,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            alignment: Alignment(-0.15, 0),
                            child: _buildImage('Logo.png', 300),
                          ),

                          TextFormField(
                            controller: _emailController,
                            focusNode: _emailFocusNode,
                            enabled: !_isLoading,
                            keyboardType: TextInputType.emailAddress,
                            style: TextStyle(color: Colors.white),
                            validator: (value) {
                              // Regex para validar formato de e-mail
                              String pattern =
                                  r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
                              RegExp regex = RegExp(pattern);

                              if (value == null || value.isEmpty) {
                                return 'Por favor, digite um e-mail';
                              } else if (!regex.hasMatch(value)) {
                                return 'Digite um e-mail válido';
                              }

                              return null; // E-mail válido
                            },
                            decoration: InputDecoration(
                              labelText: 'E-mail',
                              hintText: 'Digite seu e-mail',
                              hintStyle: TextStyle(color: Colors.white),
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(
                                Icons.email,
                                color: Colors.white,
                              ),
                              labelStyle: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.normal,
                              ),

                              // Borda quando o campo está habilitado mas não focado
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.blueGrey.shade400,
                                  width: 1.5,
                                ),
                              ),
                              // Borda quando o campo está focado
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 2.0,
                                ),
                              ),
                              // Borda quando há erro de validação
                              errorBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.red,
                                  width: 1.5,
                                ),
                              ),
                              // Borda quando há erro e o campo está focado
                              focusedErrorBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.red,
                                  width: 2.0,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 20),
                          TextFormField(
                            key: _senhaFieldKey,
                            controller: _senhaController,
                            focusNode: _senhaFocusNode,
                            enabled: !_isLoading,
                            obscureText: _obscurePassword,

                            style: TextStyle(color: Colors.white),

                            validator: (value) {
                              if (_erroSenha != null) {
                                return _erroSenha;
                              }

                              if (value == null || value.isEmpty) {
                                return 'Por favor, digite uma senha';
                              } else if (value.length < 6) {
                                return 'A senha deve ter pelo menos 6 caracteres';
                              }
                              return null; // Senha válida
                            },

                            decoration: InputDecoration(
                              labelText: 'Senha',
                              hintText: 'Digite sua senha',
                              hintStyle: TextStyle(color: Colors.white),
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(
                                Icons.lock_outline,
                                color: Colors.white,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              labelStyle: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.normal,
                              ),

                              // Borda quando o campo está habilitado mas não focado
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.blueGrey.shade400,
                                  width: 1.5,
                                ),
                              ),
                              // Borda quando o campo está focado
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.white,
                                  width: 2.0,
                                ),
                              ),
                              // Borda quando há erro de validação
                              errorBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.red,
                                  width: 1.5,
                                ),
                              ),
                              // Borda quando há erro e o campo está focado
                              focusedErrorBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.red,
                                  width: 2.0,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 10),

                          // ← ADICIONE O SWITCHLISTTILE AQUI
                          Offstage(
                            offstage: tecladoAberto,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withOpacity(0.15),
                                        Colors.white.withOpacity(0.05),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: SwitchListTile(
                                    title: Text(
                                      'Manter conectado',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                    value: _manterConectado,
                                    onChanged: (bool value) {
                                      setState(() {
                                        _manterConectado = value;
                                      });
                                    },
                                    activeColor: Colors.blueAccent,
                                    inactiveTrackColor: Colors.white24,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          SizedBox(height: 10),

                          Offstage(
                            offstage: tecladoAberto,
                            child: ElevatedButton(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => EsqueciSenha(),
                                        ),
                                      );
                                    },
                              style: ButtonStyle(
                                backgroundColor: WidgetStateProperty.all(
                                  Colors.transparent,
                                ),
                                elevation: WidgetStateProperty.all(0),
                                shadowColor: WidgetStateProperty.all(
                                  Colors.transparent,
                                ),
                                overlayColor: WidgetStateProperty.all(
                                  Colors.transparent,
                                ),
                                foregroundColor: WidgetStateProperty.all(
                                  Colors.white,
                                ),
                              ),
                              child: Text('Esqueci minha senha'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Spacer(flex: 3),
              ],
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              left: 0,
              right: 0,
              bottom: _getBottomPosition(bottomInset),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: 180,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.25),
                            Colors.white.withOpacity(0.1),
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
                        onTap: _isLoading ? null : _fazerLogin,
                        child: const Center(
                          child: Text(
                            'Entrar',
                            style: TextStyle(fontSize: 25, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            Offstage(
              offstage: tecladoAberto,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => Cadastro()),
                      );
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(
                        Colors.transparent,
                      ),
                      elevation: WidgetStateProperty.all(0),
                      shadowColor: WidgetStateProperty.all(Colors.transparent),
                      overlayColor: WidgetStateProperty.all(Colors.transparent),
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                    ),
                    child: Text('Cadastrar-se'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getBottomPosition(double bottomInset) {
    if (bottomInset > 0) {
      if (_emailFocused) {
        return bottomInset -
            300; // Ajuste do botao entrar quando email está focado
      } else if (_senhaFocused) {
        return bottomInset -
            360; // Ajuste do botao entrar quando senha está focado
      } else {
        return bottomInset + 60; // Fallback quando teclado está aberto
      }
    }
    // Teclado fechado
    return 250;
  }

  Future<void> _fazerLogin() async {
    setState(() {
      _erroSenha = null;
    });

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final resultado = await LocalService.login(
        _emailController.text.trim(),
        _senhaController.text,
        manterConectado: _manterConectado,
      );

      //==================== Exibir todos os usuários no console - Debug ===================

      final usuarios = await DB.instance.listarTodosUsuarios();

      print('Total de usuários: ${usuarios.length}');

      for (var usuario in usuarios) {
        print('ID: ${usuario['id']}');
        print('Nome: ${usuario['nome']}');
        print('Email: ${usuario['email']}');
        print('Senha: ${usuario['senha']}');
        print('---');
      }
      //==================================================================================

      if (resultado['success'] == true) {
        // Login bem-sucedido
        final usuario = resultado['user'];

        if (mounted) {
          // Sincronizar dados do usuário com Firebase
          SyncService.instance.sincronizarTudo(usuario['id']);

          // Navegar para página inicial
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => Inicial(usuarioId: usuario['id']),
            ),
          );
        }
      } else {
        // Login falhou
        setState(() {
          _erroSenha = resultado['message'] ?? 'E-mail ou senha incorretos';
        });
        _senhaFieldKey.currentState?.validate();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro inesperado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

