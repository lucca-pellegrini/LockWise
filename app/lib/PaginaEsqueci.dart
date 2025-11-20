import 'package:fechaduraflow/PaginaLogin.dart';
import 'package:flutter/material.dart';
import 'PaginaChave.dart';
import 'LocalService.dart';
import 'dart:ui';

class EsqueciSenha extends StatefulWidget {
  const EsqueciSenha({super.key});

  @override
  State<EsqueciSenha> createState() => _EsqueciSenhaState();
}

class _EsqueciSenhaState extends State<EsqueciSenha> {
  bool _isLoading = false;
  final TextEditingController _contatoController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _errorMessage;

  Widget _buildImage(String assetName, [double width = 350]) {
    return Image.asset('images/$assetName', width: width);
  }

  @override
  void dispose() {
    _contatoController.dispose();
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
          title: Text(
            'Esqueci minha senha',
            style: TextStyle(color: Colors.white),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          iconTheme: IconThemeData(size: 30.0),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => LoginPage()),
              );
            },
          ),
        ),

        body: Stack(
          children: [
            SizedBox(
              height:
                  MediaQuery.of(context).size.height -
                  56.0 -
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
                              controller: _contatoController,
                              enabled: !_isLoading,
                              onChanged: (String value) {
                                print('Valor digitado: $value');
                              },
                              keyboardType: TextInputType.emailAddress,
                              style: TextStyle(color: Colors.white),
                              validator: (value) {
                                if (_errorMessage != null) {
                                  return _errorMessage;
                                }

                                if (value == null || value.isEmpty) {
                                  return 'Por favor, digite um e-mail ou numero de telefone';
                                }
                                // Regex para validar formato de e-mail
                                String patternEmail =
                                    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
                                RegExp regexEmail = RegExp(patternEmail);

                                String patternPhone =
                                    r'^(?:(?:\+|00)?(55)\s?)?(?:\(?([1-9][0-9])\)?\s?)?(?:((?:9\d|[2-9])\d{3})\-?(\d{4}))$';
                                RegExp regexPhone = RegExp(patternPhone);

                                if (!regexEmail.hasMatch(value) &&
                                    !regexPhone.hasMatch(value)) {
                                  return 'Digite um e-mail ou numero de telefone válido';
                                }
                                return null; // E-mail ou numero de telefone válido
                              },
                              decoration: InputDecoration(
                                labelText: 'E-mail ou numero do telefone',
                                labelStyle: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.normal,
                                ),

                                hintText:
                                    'Digite seu e-mail ou numero do telefone',
                                hintStyle: TextStyle(color: Colors.white),

                                border: OutlineInputBorder(),
                                prefixIcon: Icon(
                                  Icons.contact_support_outlined,
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

                            SizedBox(height: 30),

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
                                    onTap: _isLoading
                                        ? null
                                        : _buscarUsuarioPorEmailOuTelefone,
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 30,
                                        vertical: 10,
                                      ),
                                      child: Text(
                                        'Continuar',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 25,
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
                  Spacer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _buscarUsuarioPorEmailOuTelefone() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final resultado = await LocalService.validarContato(
        _contatoController.text,
      );

      if (resultado['success'] == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Chave(contato: _contatoController.text),
          ),
        );
      } else {
        setState(() {
          _errorMessage = resultado['message'] ?? 'Contato não encontrado';
        });
        _formKey.currentState?.validate();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao tentar encontrar o usuario: $e';
      });
      _formKey.currentState?.validate();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}

