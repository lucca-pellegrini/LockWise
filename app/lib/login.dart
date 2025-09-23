import 'package:flutter/material.dart';
import 'home.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _obscurePassword = true;
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Login', style: TextStyle(color: Colors.blueAccent)),
        centerTitle: true,
        backgroundColor: Colors.white10,
      ),
      body: Stack(
        children: [
          SizedBox(
            height:
                MediaQuery.of(context).size.height -
                190.0 -
                MediaQuery.of(context).viewInsets.bottom,
            child: Column(
              children: [
                Spacer(),
                Center(
                  child: Form(
                    key: _formKey,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            onChanged: (String value) {
                              print('Valor digitado: $value');
                            },
                            keyboardType: TextInputType.emailAddress,
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
                              labelText: 'E-mail',
                              hintText: 'Digite seu e-mail',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.email),
                              labelStyle: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ),
                          SizedBox(height: 20),
                          TextFormField(
                            onChanged: (String value) {
                              print('Valor digitado: $value');
                            },
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
                              labelText: 'Senha',
                              hintText: 'Digite sua senha',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.lock_outline),
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
                              ),
                              labelStyle: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              //Mudar de pagina
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
                                Colors.blueAccent,
                              ),
                            ),
                            child: Text('Esqueci minha senha'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              if (_formKey.currentState!.validate()) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => Inicial(),
                                  ),
                                );
                              }
                            },
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.all(
                                Colors.blueAccent,
                              ),
                              foregroundColor: WidgetStateProperty.all(
                                Colors.white,
                              ),
                              padding: WidgetStateProperty.all(
                                EdgeInsets.symmetric(
                                  horizontal: 30,
                                  vertical: 10,
                                ),
                              ),
                              textStyle: WidgetStateProperty.all(
                                TextStyle(fontSize: 25),
                              ),
                            ),
                            child: Text('Entrar'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Spacer(),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: ElevatedButton(
                onPressed: () {
                  //Mudar de pagina
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(Colors.transparent),
                  elevation: WidgetStateProperty.all(0),
                  shadowColor: WidgetStateProperty.all(Colors.transparent),
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  foregroundColor: WidgetStateProperty.all(Colors.blueAccent),
                ),
                child: Text('Cadastrar-se'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
