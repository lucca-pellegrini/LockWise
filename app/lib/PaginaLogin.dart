import 'package:fechaduraflow/PaginaEsqueci.dart';
import 'package:flutter/material.dart';
import 'PaginaInicial.dart';
import 'PaginaCadastro.dart';
import 'database.dart';
import 'LocalService.dart';
import 'dart:ui';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _obscurePassword = true;
  bool _isLoading = false;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _senhaController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _senhaFieldKey = GlobalKey<FormFieldState>();
  String? _erroSenha;

  Widget _buildImage(String assetName, [double width = 350]) {
    return Image.asset('images/$assetName', width: width);
  }

  @override
  void initState() {
    super.initState();
    _verificarLoginAutomatico();
  }

  Future<void> _verificarLoginAutomatico() async {
    final estaLogado = await LocalService.estaLogado();

    if (estaLogado && mounted) {
      // Obter userId do token
      final userId = await LocalService.getUserId();

      if (userId != null) {
        // Já está logado, ir direto para tela inicial
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            SizedBox(
              height:
                  MediaQuery.of(context).size.height -
                  56.0 -
                  MediaQuery.of(context).viewInsets.bottom,
              child: Column(
                children: [
                  Spacer(flex: 2),
                  Center(
                    child: Form(
                      key: _formKey,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            //Imagem de logo
                            Container(
                              alignment: Alignment(-0.15, 0),
                              child: _buildImage('Logo.png', 300),
                            ),

                            TextFormField(
                              controller: _emailController,
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

                            ElevatedButton(
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

                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),

                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 10,
                                  sigmaY: 10,
                                ),

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
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 30,
                                        vertical: 10,
                                      ),
                                      child: Text(
                                        'Entrar',
                                        style: TextStyle(
                                          fontSize: 25,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Spacer(flex: 2),
                ],
              ),
            ),
            Align(
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
          ],
        ),
      ),
    );
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
      // Fazer login usando LocalService
      final resultado = await LocalService.login(
        _emailController.text.trim(),
        _senhaController.text,
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

