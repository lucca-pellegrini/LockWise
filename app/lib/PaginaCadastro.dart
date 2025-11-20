import 'package:flutter/material.dart';
import 'PaginaLogin.dart';
import 'database.dart';
import 'dart:ui';

class Cadastro extends StatefulWidget {
  const Cadastro({super.key});

  @override
  State<Cadastro> createState() => _CadastroState();
}

class _CadastroState extends State<Cadastro> {
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _sobrenomeController = TextEditingController();
  final TextEditingController _telefoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _senhaController = TextEditingController();
  final TextEditingController _senhaConfirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Widget _buildImage(String assetName, [double width = 350]) {
    return Image.asset('images/$assetName', width: width);
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _sobrenomeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _senhaConfirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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

      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Cadastro', style: TextStyle(color: Colors.white)),

          iconTheme: IconThemeData(color: Colors.white, size: 30.0),

          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),

        body: Stack(
          children: [
            SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.of(context).size.height -
                      AppBar().preferredSize.height -
                      MediaQuery.of(context).padding.top,
                ),

                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Center(
                      child: Form(
                        key: _formKey,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextFormField(
                                controller: _nomeController,
                                onChanged: (String value) {
                                  print('Valor digitado: $value');
                                },
                                keyboardType: TextInputType.name,
                                style: TextStyle(color: Colors.white),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Por favor, digite um nome';
                                  }
                                  if (value.length < 3) {
                                    return 'O nome deve ter pelo menos 3 caracteres';
                                  }
                                  return null; // nome válido
                                },
                                decoration: InputDecoration(
                                  hintText: 'Digite seu nome',
                                  hintStyle: TextStyle(color: Colors.white),

                                  labelText: 'Nome',
                                  labelStyle: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.normal,
                                  ),

                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(
                                    Icons.person_outline,
                                    color: Colors.white,
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
                                ),
                              ),

                              SizedBox(height: 20),

                              TextFormField(
                                controller: _sobrenomeController,
                                onChanged: (String value) {
                                  print('Valor digitado: $value');
                                },
                                keyboardType: TextInputType.name,
                                style: TextStyle(color: Colors.white),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Por favor, digite seu sobrenome';
                                  }
                                  if (value.length < 3) {
                                    return 'O sobrenome deve ter pelo menos 3 caracteres';
                                  }
                                  return null; // sobrenome válida
                                },
                                decoration: InputDecoration(
                                  hintText: 'Digite seu sobrenome',
                                  hintStyle: TextStyle(color: Colors.white),

                                  labelText: 'Sobrenome',
                                  labelStyle: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.normal,
                                  ),

                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(
                                    Icons.person_outline,
                                    color: Colors.white,
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
                                ),
                              ),

                              SizedBox(height: 20),

                              TextFormField(
                                controller: _telefoneController,
                                onChanged: (String value) {
                                  print('Valor digitado: $value');
                                },
                                keyboardType: TextInputType.phone,
                                style: TextStyle(color: Colors.white),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Por favor, digite um numedo de telefone';
                                  }
                                  // Regex para validar formato de telefone
                                  String pattern =
                                      r'^(?:(?:\+|00)?(55)\s?)?(?:\(?([1-9][0-9])\)?\s?)?(?:((?:9\d|[2-9])\d{3})\-?(\d{4}))$';
                                  RegExp regex = RegExp(pattern);
                                  if (!regex.hasMatch(value)) {
                                    return 'Digite um telefone válido';
                                  }
                                  return null; // telefone válido
                                },
                                decoration: InputDecoration(
                                  hintText: 'Digite seu numero',
                                  hintStyle: TextStyle(color: Colors.white),

                                  labelText: 'Numero de Telefone',
                                  labelStyle: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.normal,
                                  ),

                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(
                                    Icons.phone_enabled_outlined,
                                    color: Colors.white,
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
                                ),
                              ),

                              SizedBox(height: 20),

                              TextFormField(
                                controller: _emailController,
                                onChanged: (String value) {
                                  print('Valor digitado: $value');
                                },
                                keyboardType: TextInputType.emailAddress,
                                style: TextStyle(color: Colors.white),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Por favor, digite um e-mail';
                                  }
                                  // Regex para validar formato de e-mail
                                  String pattern =
                                      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
                                  RegExp regex = RegExp(pattern);
                                  if (!regex.hasMatch(value)) {
                                    return 'Digite um e-mail válido';
                                  }
                                  return null; // E-mail válido
                                },
                                decoration: InputDecoration(
                                  hintText: 'Digite seu e-mail',
                                  hintStyle: TextStyle(color: Colors.white),

                                  labelText: 'E-mail',
                                  labelStyle: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.normal,
                                  ),

                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(
                                    Icons.email_outlined,
                                    color: Colors.white,
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
                                ),
                              ),

                              SizedBox(height: 20),

                              TextFormField(
                                controller: _senhaController,
                                onChanged: (String value) {
                                  print('Valor digitado: $value');
                                },
                                style: TextStyle(color: Colors.white),
                                obscureText: _obscurePassword,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Por favor, digite uma senha';
                                  }
                                  if (value.length < 6) {
                                    return 'A senha deve ter pelo menos 6 caracteres';
                                  }
                                  return null; // Senha válida
                                },
                                decoration: InputDecoration(
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    color: Colors.white,
                                  ),

                                  hintText: 'Digite sua senha',
                                  hintStyle: TextStyle(color: Colors.white),

                                  labelText: 'Senha',
                                  labelStyle: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.normal,
                                  ),

                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(
                                    Icons.lock_outline,
                                    color: Colors.white,
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
                                ),
                              ),

                              SizedBox(height: 20),

                              TextFormField(
                                controller: _senhaConfirmController,
                                onChanged: (String value) {
                                  print('Valor digitado: $value');
                                },
                                style: TextStyle(color: Colors.white),
                                obscureText: _obscurePasswordConfirm,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Por favor, confirme sua senha';
                                  }
                                  if (value != _senhaController.text) {
                                    return 'As senhas não coincidem';
                                  }
                                  return null; // Senha válida
                                },
                                decoration: InputDecoration(
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePasswordConfirm
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePasswordConfirm =
                                            !_obscurePasswordConfirm;
                                      });
                                    },
                                    color: Colors.white,
                                  ),

                                  hintText: 'Digite sua senha novamente',
                                  hintStyle: TextStyle(color: Colors.white),

                                  labelText: 'Confirmar Senha',
                                  labelStyle: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.normal,
                                  ),

                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(
                                    Icons.check,
                                    color: Colors.white,
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
                                ),
                              ),

                              SizedBox(height: 25),

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
                                      onTap: () async {
                                        if (_formKey.currentState!.validate()) {
                                          bool _isLoading = true;

                                          try {
                                            String nome =
                                                '${_nomeController.text} ${_sobrenomeController.text}';

                                            await DB.instance.inserirUsuario({
                                              'nome': nome,
                                              'email': _emailController.text,
                                              'telefone':
                                                  _telefoneController.text,
                                              'senha': _senhaController.text,
                                            });

                                            _isLoading = false;

                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    LoginPage(),
                                              ),
                                            );
                                            _nomeController.clear();
                                            _sobrenomeController.clear();
                                            _emailController.clear();
                                            _senhaController.clear();
                                            _senhaConfirmController.clear();
                                          } catch (e) {
                                            print(
                                              'Erro ao adicionar fechadura: $e',
                                            );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Erro ao adicionar usuario',
                                                ),
                                              ),
                                            );
                                            _isLoading = false;
                                          }
                                        }
                                      },

                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 30,
                                          vertical: 10,
                                        ),
                                        child: Text(
                                          'Criar Conta',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
