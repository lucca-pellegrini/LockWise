import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;
import 'PaginaDetalhe.dart';
import 'PaginaSobre.dart';
import 'PaginaNotificação.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'database.dart';
import 'LocalService.dart';
import 'dart:ui';
import 'models/nav_item_model.dart';

class Inicial extends StatefulWidget {
  final int usuarioId;

  Inicial({super.key, required this.usuarioId});

  @override
  State<Inicial> createState() => _InicialState();
}

class _InicialState extends State<Inicial> {
  bool _showExtraButtons = false;
  bool _isLoading = false;
  final DB db = DB.instance;
  List<Map<String, dynamic>> cartoes = [];
  int selectedNavIndex = 0;
  List<rive.SMIBool?> riveIconInput = List<rive.SMIBool?>.filled(
    bottomNavItems.length,
    null,
  );
  List<rive.StateMachineController?> riveControllers =
      List<rive.StateMachineController?>.filled(bottomNavItems.length, null);

  Widget _buildImage(String assetName, [double width = 350]) {
    return Image.asset('images/$assetName', width: width);
  }

  @override
  void initState() {
    super.initState();
    _carregarFechaduras();
  }

  void animateTheIcon(int index) {
    if (index < 0 || index >= riveIconInput.length) return;
    final input = riveIconInput[index];
    if (input == null) {
      // Se o artboard ainda não inicializou, tenta novamente em breve
      Future.delayed(
        const Duration(milliseconds: 50),
        () => animateTheIcon(index),
      );
      return;
    }
    input.value = true;
    Future.delayed(const Duration(milliseconds: 800), () {
      final i = riveIconInput[index];
      if (i != null) i.value = false;
    });
  }

  void riveOnInIt(
    int index,
    rive.Artboard artboard, {
    required String stateMachineName,
  }) {
    final controller = rive.StateMachineController.fromArtboard(
      artboard,
      stateMachineName,
    );
    if (controller == null) return;

    artboard.addController(controller);
    riveControllers[index]?.dispose();
    riveControllers[index] = controller;

    final input = controller.findInput<bool>('active') as rive.SMIBool?;
    if (input != null) {
      riveIconInput[index] = input;
    }
  }

  @override
  void dispose() {
    for (var controller in riveControllers) {
      controller?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,

      child: Container(
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
            title: Text(
              'Minhas LockWise',
              style: TextStyle(color: Colors.white),
            ),
            centerTitle: true,
            backgroundColor: Colors.transparent,

            iconTheme: IconThemeData(color: Colors.white, size: 40.0),
          ),

          drawer: NavigationDrawer(usuarioId: widget.usuarioId),

          body: OrientationBuilder(
            builder: (context, orientation) {
              final gridDelegate = orientation == Orientation.portrait
                  ? SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10.0,
                      crossAxisSpacing: 10.0,
                      childAspectRatio: 3 / 2,
                    )
                  : SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 10.0,
                      crossAxisSpacing: 10.0,
                      childAspectRatio: 3 / 2,
                    );

              return ReorderableGridView.builder(
                padding: const EdgeInsets.all(16.0),
                gridDelegate: gridDelegate,
                itemCount: cartoes.length,
                dragStartDelay: const Duration(milliseconds: 150),
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = cartoes.removeAt(oldIndex);
                    cartoes.insert(newIndex, item);
                  });
                },

                dragWidgetBuilder: (index, child) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blueAccent, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blueAccent.withOpacity(0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: child,
                  );
                },

                itemBuilder: (context, index) {
                  final cartao = cartoes[index];

                  return Card.outlined(
                    key: ValueKey(cartao['id']),
                    color: Colors.transparent,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ClipRRect(
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
                            border: Border.all(
                              color: Colors.white.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: _ConteudoCartao(
                            Name: cartao['name'],
                            icon: cartao['icon'],
                            fechaduraId: cartao['id'],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),

          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              if (_showExtraButtons) ...[
                _buildGlassFloatingButton(
                  icon: Icons.add,
                  heroTag: "add",
                  mini: true,
                  onPressed: () {
                    setState(() {
                      _showAddCardDialog();
                    });
                  },
                ),
                SizedBox(height: 10),

                _buildGlassFloatingButton(
                  icon: Icons.close,
                  heroTag: "delete",
                  onPressed: () {
                    if (cartoes.isNotEmpty) {
                      _showRemoveCardDialog();
                    }
                  },
                ),
                SizedBox(height: 10),
              ],

              _buildGlassFloatingButton(
                icon: Icons.edit,
                heroTag: "edit",
                onPressed: () {
                  setState(() {
                    _showExtraButtons = !_showExtraButtons;
                  });
                },
                mini: false,
              ),
            ],
          ),

          bottomNavigationBar: CurvedGlassNavigationBar(
            selectedIndex: selectedNavIndex,
            onTap: (index) {
              setState(() => selectedNavIndex = index);
            },
            riveIconInput: riveIconInput,
            animateTheIcon: animateTheIcon,
            riveOnInit: riveOnInIt,
          ),
        ),
      ),
    );
  }

  void _showRemoveCardDialog() {
    if (cartoes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum cartão para remover')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: _GlassDialog(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: const Text(
                          'Remover Fechadura',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.maxFinite,
                      height: 220,
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.blueAccent,
                              ),
                            )
                          : ListView.builder(
                              itemCount: cartoes.length,
                              itemBuilder: (context, index) {
                                final cartao = cartoes[index];
                                return ListTile(
                                  leading: Icon(
                                    cartao['icon'],
                                    color: Colors.white,
                                  ),
                                  title: Text(
                                    cartao['name'],
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  trailing: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onTap: () async {
                                    try {
                                      setState(
                                        () => _isLoading = true,
                                      ); // atualiza estado no parent
                                      setStateDialog(
                                        () {},
                                      ); // força rebuild do dialog

                                      await DB.instance.deletarFechadura(
                                        cartao['id'],
                                      );
                                      await _carregarFechaduras(); // recarrega lista (parent)

                                      setStateDialog(
                                        () {},
                                      ); // reflete nova lista dentro do dialog
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Fechadura "${cartao['name']}" removida',
                                          ),
                                        ),
                                      );

                                      if (cartoes.isEmpty) {
                                        Navigator.of(
                                          context,
                                        ).pop(); // fecha se acabou
                                      }
                                    } catch (e) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Erro ao remover'),
                                        ),
                                      );
                                    } finally {
                                      setState(() => _isLoading = false);
                                      setStateDialog(() {});
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 20, bottom: 10),
                        child: _GlassDialogButton(
                          text: 'Fechar',
                          onPressed: () => Navigator.of(context).pop(),
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddCardDialog() {
    final TextEditingController nomeController = TextEditingController();
    IconData iconeSelecionado = Icons.star;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: _GlassDialog(
                child: Column(
                  mainAxisSize: MainAxisSize.min,

                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          'Adicionar Nova Fechadura',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 20),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),

                      child: TextFormField(
                        controller: nomeController,
                        style: TextStyle(color: Colors.white),

                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Por favor, insira o nome da fechadura';
                          } else if (value.length > 15) {
                            return 'O nome deve ter pelo menos 3 caracteres';
                          }
                          return null;
                        },

                        decoration: InputDecoration(
                          labelText: 'Nome da Fechadura',
                          labelStyle: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.normal,
                          ),

                          hintText: 'Digite o nome da fechadura',
                          hintStyle: TextStyle(color: Colors.white),

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
                    ),
                    SizedBox(height: 10),

                    Text('Selecione um ícone:'),
                    SizedBox(height: 8),

                    Wrap(
                      spacing: 10,
                      runSpacing: 7,
                      children: [
                        _buildIconOption(
                          Icons.star,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                        _buildIconOption(
                          Icons.home,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                        _buildIconOption(
                          Icons.lock,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                        _buildIconOption(
                          Icons.security,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                        _buildIconOption(
                          Icons.door_front_door,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                        _buildIconOption(
                          Icons.key,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                      ],
                    ),

                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.only(right: 20, bottom: 10),

                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,

                          children: [
                            _GlassDialogButton(
                              text: 'Cancelar',
                              onPressed: () => Navigator.of(context).pop(),
                              color: Colors.red,
                            ),
                            SizedBox(width: 10),

                            _GlassDialogButton(
                              text: 'Adicionar',
                              onPressed: () async {
                                if (nomeController.text.isNotEmpty) {
                                  try {
                                    int iconeCodePoint =
                                        iconeSelecionado.codePoint;
                                    await DB.instance.inserirFechadura({
                                      'usuario_id': widget.usuarioId,
                                      'nome': nomeController.text,
                                      'icone_code_point': iconeCodePoint,
                                      'notificacoes': 1,
                                      'acesso_remoto': 1,
                                    });
                                    await _carregarFechaduras();
                                    Navigator.of(context).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Fechadura "${nomeController.text}" adicionada!',
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    print('Erro ao adicionar fechadura: $e');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Erro ao adicionar fechadura',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildIconOption(
    IconData icon,
    IconData iconeSelecionado,
    StateSetter setStateDialog,
    Function(IconData) onSelected,
  ) {
    return GestureDetector(
      onTap: () {
        setStateDialog(() {
          onSelected(icon);
        });
      },

      child: Container(
        padding: EdgeInsets.all(8),

        decoration: BoxDecoration(
          border: Border.all(
            color: iconeSelecionado == icon ? Colors.white : Colors.grey,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),

        child: Icon(
          icon,
          color: iconeSelecionado == icon ? Colors.white : Colors.grey,
          size: 30,
        ),
      ),
    );
  }

  Future<void> _carregarFechaduras() async {
    setState(() => _isLoading = true);

    try {
      print('Buscando fechaduras para usuário ID: ${widget.usuarioId}');
      // Buscar fechaduras do banco de dados
      final fechaduras = await DB.instance.listarFechadurasDoUsuario(
        widget.usuarioId,
      );
      print('Fechaduras encontradas: ${fechaduras.length}');

      setState(() {
        // Converter para o formato dos cartões
        cartoes = fechaduras
            .map(
              (f) => {
                'id': f['id'],
                'name': f['nome'],
                'icon': IconData(
                  f['icone_code_point'],
                  fontFamily: 'MaterialIcons',
                ),
                'notificacoes': f['notificacoes'],
                'acesso_remoto': f['acesso_remoto'],
              },
            )
            .toList();
        _isLoading = false;
      });

      print('${cartoes.length} fechaduras carregadas');
    } catch (e) {
      print('Erro ao carregar fechaduras: $e');
      setState(() => _isLoading = false);
    }
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
  final double? opacity;

  const _GlassDialogButton({
    required this.text,
    required this.onPressed,
    required this.color,
    this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          decoration: BoxDecoration(
            color: color.withOpacity(opacity ?? 0.13),
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

class _ConteudoCartao extends StatelessWidget {
  const _ConteudoCartao({
    required this.Name,
    required this.icon,
    required this.fechaduraId,
  });
  final String Name;
  final IconData icon;
  final int fechaduraId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 100,
      child: InkWell(
        splashColor: Colors.blue.withAlpha(30),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LockDetails(fechaduraId: fechaduraId),
            ),
          );
          debugPrint('Card tapped.');
        },

        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(Name, style: TextStyle(color: Colors.white)),
            SizedBox(width: 10),
            Icon(icon, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class NavigationDrawer extends StatefulWidget {
  final int usuarioId;

  const NavigationDrawer({super.key, required this.usuarioId});

  @override
  State<NavigationDrawer> createState() => _NavigationDrawerState();
}

class _NavigationDrawerState extends State<NavigationDrawer> {
  Map<String, dynamic>? usuario;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarUsuario();
  }

  Future<void> _carregarUsuario() async {
    try {
      final user = await DB.instance.buscarUsuarioPorId(widget.usuarioId);
      setState(() {
        usuario = user;
        _isLoading = false;
      });
    } catch (e) {
      print('Erro ao carregar dados do usuário: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Drawer(
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[buildHeader(context), buildMenuItems(context)],
      ),
    ),
  );

  Widget buildHeader(BuildContext context) => Container(
    color: Colors.blueAccent,
    padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
    child: Column(
      children: <Widget>[
        const SizedBox(height: 12),
        CircleAvatar(
          radius: 52,
          backgroundColor: Colors.white,
          child: Icon(Icons.person, size: 50, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        _isLoading
            ? CircularProgressIndicator(color: Colors.blueAccent)
            : Text(
                usuario != null ? usuario!['nome'] : 'Usuário',
                style: TextStyle(fontSize: 20, color: Colors.white),
              ),
        const SizedBox(height: 12),
      ],
    ),
  );

  Widget buildMenuItems(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    child: Wrap(
      runSpacing: 16,
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.home_outlined, color: Colors.blueAccent),
          title: const Text('Início'),
          onTap: () => Navigator.of(context).pop(),
        ),
        ListTile(
          leading: const Icon(
            Icons.notifications_outlined,
            color: Colors.blueAccent,
          ),
          title: const Text('Notificações'),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const Notificacao()),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.info_outline, color: Colors.blueAccent),
          title: const Text('Sobre'),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const Sobre()),
            );
          },
        ),
        ListTile(
          leading: const Icon(
            Icons.no_accounts_outlined,
            color: Colors.blueAccent,
          ),
          title: const Text('Deletar Conta'),
          onTap: () async {
            try {
              await DB.instance.deletarUsuario(widget.usuarioId);
              print('Conta deletada com sucesso.');
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            } catch (e) {
              print('Erro ao deletar conta: $e');
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.blueAccent),
          title: const Text('Sair'),
          onTap: () async {
            Navigator.of(context).pop();
            Navigator.of(context).pop();

            await LocalService.logout();
          },
        ),
      ],
    ),
  );
}

Widget _buildGlassFloatingButton({
  required IconData icon,
  required String heroTag,
  required VoidCallback onPressed,
  bool mini = true,
}) {
  return Hero(
    tag: heroTag,

    child: ClipRRect(
      borderRadius: BorderRadius.circular(mini ? 28 : 28),

      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),

        child: Container(
          width: mini ? 40 : 56,
          height: mini ? 40 : 56,

          decoration: BoxDecoration(
            color: Colors.blueAccent.withOpacity(0.2),
            borderRadius: BorderRadius.circular(mini ? 28 : 28),
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
          ),

          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(mini ? 28 : 28),
              child: Icon(icon, color: Colors.white, size: mini ? 20 : 24),
            ),
          ),
        ),
      ),
    ),
  );
}

class CurvedGlassNavigationBar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onTap;
  final List<rive.SMIBool?> riveIconInput;
  final Function(int) animateTheIcon;
  final Function(int, rive.Artboard, {required String stateMachineName})
  riveOnInit;

  const CurvedGlassNavigationBar({
    Key? key,
    required this.selectedIndex,
    required this.onTap,
    required this.riveIconInput,
    required this.animateTheIcon,
    required this.riveOnInit,
  }) : super(key: key);

  @override
  State<CurvedGlassNavigationBar> createState() =>
      _CurvedGlassNavigationBarState();
}

class _CurvedGlassNavigationBarState extends State<CurvedGlassNavigationBar> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: 80,
        margin: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Container com Glass Effect
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.19),
                          Colors.white.withOpacity(0.13),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Items da Navigation
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(bottomNavItems.length, (index) {
                    final isSelected = widget.selectedIndex == index;
                    final riveIcon = bottomNavItems[index].rive;

                    return GestureDetector(
                      onTap: () {
                        // Primeiro atualiza o item selecionado (causa rebuild do pai)
                        widget.onTap(index); // causa o lift
                        Future.delayed(const Duration(milliseconds: 100), () {
                          widget.animateTheIcon(index); // dispara após o lift
                        });
                      },
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 300),
                        curve: Curves.easeInOutCubic,
                        transform: Matrix4.translationValues(
                          0,
                          isSelected ? -20 : 0,
                          0,
                        ),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: isSelected
                              ? BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.3),
                                      Colors.white.withOpacity(0.2),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.5),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.3),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                )
                              : null,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                height: 36,
                                width: 36,
                                child: Opacity(
                                  opacity: isSelected ? 1.0 : 0.5,
                                  child: rive.RiveAnimation.asset(
                                    riveIcon.src,
                                    artboard: riveIcon.artboard,
                                    key: ValueKey('nav_rive_$index'),
                                    onInit: (artboard) {
                                      widget.riveOnInit(
                                        index,
                                        artboard,
                                        stateMachineName:
                                            riveIcon.stateMachineName,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

