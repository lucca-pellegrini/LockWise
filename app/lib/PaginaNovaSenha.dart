import 'package:flutter/material.dart';
import 'PaginaLogin.dart';
import 'PaginaEsqueci.dart';
import 'database.dart';
import 'dart:ui';

class NovaSenha extends StatefulWidget {
  final String contato;

  const NovaSenha({super.key, required this.contato});

  @override
  State<NovaSenha> createState() => _NovaSenhaState();
}

class _NovaSenhaState extends State<NovaSenha> {
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;
  bool _isLoading = false;
  final TextEditingController _senhaController = TextEditingController();
  final TextEditingController _senhaConfirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Widget _buildImage(String assetName, [double width = 350]) {
    return Image.asset('images/$assetName', width: width);
  }

  @override
  void dispose() {
    _senhaConfirmController.dispose();
    _senhaController.dispose();
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
                              controller: _senhaController,
                              onChanged: (String value) {
                                print('Valor digitado: $value');
                              },
                              style: TextStyle(color: Colors.white),
                              obscureText: _obscurePassword,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Por favor, digite uma nova senha';
                                }
                                if (value.length < 6) {
                                  return 'A senha deve ter pelo menos 6 caracteres';
                                }
                                return null; // Senha válida
                              },
                              decoration: InputDecoration(
                                labelText: 'Senha',
                                labelStyle: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.normal,
                                ),

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
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
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
                                labelText: 'Confirmar Senha',
                                labelStyle: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.normal,
                                ),

                                hintText: 'Digite sua senha novamente',
                                hintStyle: TextStyle(color: Colors.white),

                                border: OutlineInputBorder(),
                                prefixIcon: Icon(
                                  Icons.check,
                                  color: Colors.white,
                                ),
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
                                    onTap: _isLoading ? null : _atualizarSenha,
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 30,
                                        vertical: 10,
                                      ),
                                      child: _isLoading
                                          ? CircularProgressIndicator(
                                              color: Colors.white,
                                            )
                                          : Text(
                                              'Confirmar',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 25,
                                              ),
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

  Future<void> _atualizarSenha() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final linhasAfetadas = await DB.instance.atualizarSenha(
        widget.contato,
        _senhaController.text,
      );

      if (linhasAfetadas > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Senha atualizada com sucesso!')),
        );

        _senhaController.clear();
        _senhaConfirmController.clear();

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LoginPage()),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao atualizar senha')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
