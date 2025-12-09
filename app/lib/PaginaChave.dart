import 'package:fechaduraflow/PaginaEsqueci.dart';
import 'package:flutter/material.dart';
import 'PaginaNovaSenha.dart';
import 'dart:ui';

class Chave extends StatefulWidget {
  final String contato;

  const Chave({super.key, required this.contato});

  @override
  State<Chave> createState() => _ChaveState();
}

class _ChaveState extends State<Chave> {
  final TextEditingController _chaveController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Widget _buildImage(String assetName, [double width = 350]) {
    return Image.asset('images/$assetName', width: width);
  }

  @override
  void dispose() {
    _chaveController.dispose();
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

          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => EsqueciSenha()),
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
                              controller: _chaveController,
                              onChanged: (String value) {
                                print('Valor digitado: $value');
                              },
                              keyboardType: TextInputType.emailAddress,
                              style: TextStyle(color: Colors.white),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Por favor, digite o codigo recebido';
                                }

                                if (value.length < 6 || value.length > 6) {
                                  return 'A senha deve ter 6 caracteres';
                                }

                                return null; // codigo valido válido
                              },
                              decoration: InputDecoration(
                                labelText: 'Codigo',
                                labelStyle: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.normal,
                                ),

                                hintText: 'Digite seu o codigo enviado',
                                hintStyle: TextStyle(color: Colors.white),

                                border: OutlineInputBorder(),
                                prefixIcon: Icon(
                                  Icons.key,
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
                                    onTap: () {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Código reenviado com sucesso!',
                                          ),
                                          backgroundColor: Colors.green,
                                          duration: Duration(seconds: 4),
                                        ),
                                      );
                                    },

                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 30,
                                        vertical: 10,
                                      ),
                                      child: Text(
                                        'Reenviar codigo',
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

                            SizedBox(height: 20),

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
                                    onTap: () {
                                      if (_formKey.currentState!.validate()) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => NovaSenha(
                                              contato: widget.contato,
                                            ),
                                          ),
                                        );
                                        _chaveController.clear();
                                      }
                                    },

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
}
