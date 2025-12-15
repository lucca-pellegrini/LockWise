import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;
import 'PaginaDetalhe.dart';
import 'PaginaConfig.dart';
import 'PaginaNotificação.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'LocalService.dart';
import 'dart:ui';
import 'models/nav_item_model.dart';
import 'PaginaTemporaria.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:wifi_scan/wifi_scan.dart';
import 'dart:convert';
import 'dart:async';

class Inicial extends StatefulWidget {
  final String usuarioId;

  Inicial({super.key, required this.usuarioId});

  @override
  State<Inicial> createState() => _InicialState();
}

class _InicialState extends State<Inicial> {
  bool _showExtraButtons = false;
  bool _isLoading = false;
  List<Map<String, dynamic>> cartoes = [];
  List<WiFiAccessPoint> _wifiNetworks = [];
  String? selectedWifiNetwork;
  String wifiPassword = '';
  int selectedNavIndex = 0;
  List<rive.SMIBool?> riveIconInput = List<rive.SMIBool?>.filled(
    bottomNavItems.length,
    null,
  );
  List<rive.StateMachineController?> riveControllers =
      List<rive.StateMachineController?>.filled(bottomNavItems.length, null);
  Timer? _statusPollingTimer;

  Widget _buildImage(String assetName, [double width = 350]) {
    return Image.asset('images/$assetName', width: width);
  }

  @override
  void initState() {
    super.initState();
    _carregarFechaduras();
    _scanWifiNetworks();
    _startStatusPolling();
  }

  Future<void> _scanWifiNetworks() async {
    final can = await WiFiScan.instance.canGetScannedResults(
      askPermissions: true,
    );
    if (can == CanGetScannedResults.yes) {
      await WiFiScan.instance.startScan();
      final results = await WiFiScan.instance.getScannedResults();
      setState(() => _wifiNetworks = results);
    } else {
      setState(() => _wifiNetworks = []);
    }
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

  void _startStatusPolling() {
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _pollStatuses();
    });
  }

  Future<void> _pollStatuses() async {
    if (cartoes.isEmpty) return;
    final backendToken = await LocalService.getBackendToken();
    if (backendToken == null) return;
    try {
      final response = await http.get(
        Uri.parse('${LocalService.backendUrl}/devices'),
        headers: {'Authorization': 'Bearer $backendToken'},
      );
      if (response.statusCode == 200) {
        final devices = jsonDecode(response.body) as List;
        final usuario = await LocalService.getUsuarioLogado();
        final userId = usuario?['id'] as String;
        setState(() {
          for (var cartao in cartoes) {
            final device = devices.firstWhere(
              (d) => d['uuid'] == cartao['id'],
              orElse: () => null,
            );
            if (device != null) {
              final lastHeard = device['last_heard'];
              final isOnline =
                  lastHeard != null &&
                  (DateTime.now().millisecondsSinceEpoch - lastHeard) < 30000;
              final isUnlocked = device['lock_state'] == 'UNLOCKED';
              final lockedDownAt = device['locked_down_at'];
              cartao['isOnline'] = isOnline;
              cartao['isUnlocked'] = isUnlocked;
              cartao['locked_down_at'] = lockedDownAt;
            } else {
              cartao['isUnlocked'] = false;
              cartao['locked_down_at'] = null;
            }
            // Update name and icon from FireStore
            if (userId != null) {
              FirebaseFirestore.instance
                  .collection('fechaduras')
                  .doc(userId)
                  .collection('devices')
                  .doc(cartao['id'])
                  .get()
                  .then((doc) {
                    if (doc.exists) {
                      final data = doc.data();
                      final nome = data?['nome'];
                      final iconeCodePoint = data?['icone_code_point'];
                      setState(() {
                        if (nome != null && nome != cartao['name']) {
                          cartao['name'] = nome;
                        }
                        if (iconeCodePoint != null) {
                          cartao['icon'] = IconData(
                            iconeCodePoint,
                            fontFamily: 'MaterialIcons',
                          );
                        }
                      });
                    }
                  });
            }
          }
        });
      }
    } catch (e) {
      // ignore
    }
  }

  @override
  void dispose() {
    _statusPollingTimer?.cancel();
    for (var controller in riveControllers) {
      controller?.dispose();
    }
    super.dispose();
  }

  Widget _buildHome() {
    // Se está carregando, mostra loading
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: Colors.blueAccent));
    }

    // Se não tem fechaduras, mostra estado vazio
    if (cartoes.isEmpty) {
      return _buildEmptyStateHome();
    }

    // Se tem fechaduras, mostra o grid normal
    return ReorderableGridView.builder(
      padding: const EdgeInsets.all(16.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10.0,
        crossAxisSpacing: 10.0,
        childAspectRatio: 3 / 2,
      ),
      itemCount: cartoes.length,
      dragStartDelay: const Duration(milliseconds: 150),
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = cartoes.removeAt(oldIndex);
          cartoes.insert(newIndex, item);
        });
      },
      dragWidgetBuilder: (index, child) => Container(
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
      ),
      itemBuilder: (context, index) {
        final cartao = cartoes[index];
        final isOnline = cartao['isOnline'] ?? true;
        final isUnlocked = cartao['isUnlocked'] ?? false;
        Border myBorder;
        List<BoxShadow>? myShadow;
        LinearGradient myGradient;
        if (cartao['locked_down_at'] != null) {
          myGradient = LinearGradient(
            colors: [Colors.red.withOpacity(0.3), Colors.red.withOpacity(0.1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
          myBorder = Border.all(color: Colors.red, width: 3);
          myShadow = null;
        } else {
          myGradient = LinearGradient(
            colors: [
              Colors.blueAccent.withOpacity(0.3),
              Colors.blueAccent.withOpacity(0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
          myShadow = null;
          if (!isOnline) {
            myBorder = Border.all(color: Colors.orange.shade800, width: 3);
          } else if (isUnlocked) {
            myBorder = Border.all(color: Colors.green, width: 3);
          } else {
            myBorder = Border.all(
              color: Colors.white.withOpacity(0.5),
              width: 1,
            );
          }
        }
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
                  gradient: myGradient,
                  borderRadius: BorderRadius.circular(20),
                  border: myBorder,
                  boxShadow: myShadow,
                ),
                child: _ConteudoCartao(
                  Name: cartao['name'],
                  icon: cartao['icon'],
                  fechaduraId: cartao['id'],
                  isLockedDown: cartao['locked_down_at'] != null,
                  isOnline: cartao['isOnline'] ?? true,
                  isUnlocked: cartao['isUnlocked'] ?? false,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> get _pages => [
    _buildHome(), // index 0
    const Notificacao(), // index 1
    const Config(), // index 2
    const Temporaria(), // index 3
  ];

  final List<String> _appBarTitles = [
    'Minhas LockWise', // index 0
    'Notificações', // index 1
    'Configuração', // index 2
    'Acessos Temporários', // index 3
  ];

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
              _appBarTitles[selectedNavIndex],
              style: TextStyle(color: Colors.white),
            ),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            iconTheme: IconThemeData(color: Colors.white, size: 40.0),
          ),

          body: IndexedStack(index: selectedNavIndex, children: _pages),

          floatingActionButton: selectedNavIndex == 0
              ? Column(
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
                )
              : null,

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

                                      // First, unpair in backend
                                      final backendToken =
                                          await LocalService.getBackendToken();
                                      if (backendToken != null) {
                                        final response = await http.post(
                                          Uri.parse(
                                            '${LocalService.backendUrl}/unpair/${cartao['id']}',
                                          ),
                                          headers: {
                                            'Authorization':
                                                'Bearer $backendToken',
                                          },
                                        );
                                        if (response.statusCode != 200) {
                                          throw Exception(
                                            'Backend unpair failed',
                                          );
                                        }
                                      }

                                      // Remove from local list immediately
                                      setState(() {
                                        cartoes.removeWhere(
                                          (c) => c['id'] == cartao['id'],
                                        );
                                      });

                                      await FirebaseFirestore.instance
                                          .collection('fechaduras')
                                          .doc(widget.usuarioId)
                                          .collection('devices')
                                          .doc(cartao['id'])
                                          .delete();
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
    selectedWifiNetwork = null;
    wifiPassword = '';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            bool isPairing = false;

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

                    Text(
                      'Selecione um ícone:',
                      style: TextStyle(color: Colors.white),
                    ),
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
                        _buildIconOption(
                          Icons.business,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                        _buildIconOption(
                          Icons.house,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                        _buildIconOption(
                          Icons.apartment,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                        _buildIconOption(
                          Icons.cabin,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                        _buildIconOption(
                          Icons.hotel,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                        _buildIconOption(
                          Icons.store,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                        _buildIconOption(
                          Icons.shop,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                        _buildIconOption(
                          Icons.restaurant,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                        _buildIconOption(
                          Icons.school,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                        _buildIconOption(
                          Icons.church,
                          iconeSelecionado,
                          setStateDialog,
                          (icon) => iconeSelecionado = icon,
                        ),
                      ],
                    ),

                    SizedBox(height: 20),

                    Text(
                      'Configuração de WiFi:',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),

                    // WiFi Network Dropdown
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'Rede WiFi',
                          labelStyle: TextStyle(color: Colors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.blueGrey.shade400,
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.white,
                              width: 2.0,
                            ),
                          ),
                          prefixIcon: Icon(Icons.wifi, color: Colors.white),
                        ),
                        dropdownColor: Colors.blueAccent.withOpacity(0.8),
                        style: TextStyle(color: Colors.white),
                        value: selectedWifiNetwork,
                        items: _wifiNetworks
                            .where((ap) => ap.ssid.isNotEmpty)
                            .map(
                              (ap) => DropdownMenuItem<String>(
                                value: ap.ssid,
                                child: Text(ap.ssid),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          selectedWifiNetwork = value;
                          setStateDialog(() {});
                        },
                      ),
                    ),

                    SizedBox(height: 10),

                    // WiFi Password Field
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: TextFormField(
                        style: TextStyle(color: Colors.white),
                        obscureText: true,
                        onChanged: (value) {
                          wifiPassword = value;
                        },
                        decoration: InputDecoration(
                          labelText: 'Senha da Rede WiFi',
                          labelStyle: TextStyle(color: Colors.white),
                          hintText: 'Digite a senha da rede',
                          hintStyle: TextStyle(color: Colors.white),
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock, color: Colors.white),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.blueGrey.shade400,
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.white,
                              width: 2.0,
                            ),
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 20),

                    Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 10),

                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isPairing) ...[
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 10),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _GlassDialogButton(
                                  text: 'Cancelar',
                                  onPressed: () => Navigator.of(context).pop(),
                                  color: Colors.red,
                                ),
                                SizedBox(width: 10),

                                _GlassDialogButton(
                                  text: isPairing
                                      ? 'Pareando...'
                                      : 'Parear Dispositivo',
                                  onPressed: isPairing
                                      ? () {}
                                      : () async {
                                          if (nomeController.text.isNotEmpty &&
                                              selectedWifiNetwork != null &&
                                              wifiPassword.isNotEmpty) {
                                            setStateDialog(
                                              () => isPairing = true,
                                            );
                                            try {
                                              // First, send configuration to device
                                              String configData =
                                                  '${widget.usuarioId}\n$selectedWifiNetwork\n$wifiPassword';

                                              var response = await http.post(
                                                Uri.parse(
                                                  'http://192.168.4.1/configure',
                                                ),
                                                headers: {
                                                  'Content-Type': 'text/plain',
                                                },
                                                body: configData,
                                              );

                                              if (response.statusCode == 200) {
                                                // Parse device UUID from response body
                                                String deviceUuid = response
                                                    .body
                                                    .trim();

                                                // Show message to reconnect to home WiFi
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Configuração enviada. Reconecte-se à sua rede WiFi ou mobile.',
                                                    ),
                                                    duration: Duration(
                                                      seconds: 3,
                                                    ),
                                                  ),
                                                );

                                                // Wait for user to reconnect
                                                await Future.delayed(
                                                  Duration(seconds: 10),
                                                );

                                                // Success! Now add or update in Firestore with device UUID as document ID
                                                int iconeCodePoint =
                                                    iconeSelecionado.codePoint;

                                                final docRef = FirebaseFirestore
                                                    .instance
                                                    .collection('fechaduras')
                                                    .doc(widget.usuarioId)
                                                    .collection('devices')
                                                    .doc(deviceUuid);

                                                final doc = await docRef.get();
                                                if (doc.exists) {
                                                  // Update existing device
                                                  await docRef.update({
                                                    'nome': nomeController.text,
                                                    'icone_code_point':
                                                        iconeCodePoint,
                                                    'updated_at':
                                                        FieldValue.serverTimestamp(),
                                                  });
                                                } else {
                                                  // Add new device
                                                  await docRef.set({
                                                    'nome': nomeController.text,
                                                    'icone_code_point':
                                                        iconeCodePoint,
                                                    'notificacoes': 1,
                                                    'acesso_remoto': 1,
                                                    'aberto': 1,
                                                    'updated_at':
                                                        FieldValue.serverTimestamp(),
                                                  });
                                                }

                                                final fechaduraId = deviceUuid;

                                                await _carregarFechaduras();
                                                Navigator.of(context).pop();
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Fechadura "${nomeController.text}" pareada com sucesso!',
                                                    ),
                                                  ),
                                                );
                                              } else {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Erro na configuração: ${response.statusCode}. Verifique se está conectado ao LockWise AP.',
                                                    ),
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              print(
                                                'Erro ao parear dispositivo: $e',
                                              );
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Erro ao parear dispositivo. Verifique se está conectado ao LockWise AP.',
                                                  ),
                                                ),
                                              );
                                            }
                                          } else {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Preencha todos os campos obrigatórios.',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                  color: Colors.white,
                                ),
                              ],
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
      // Buscar fechaduras do Firestore
      final querySnapshot = await FirebaseFirestore.instance
          .collection('fechaduras')
          .doc(widget.usuarioId)
          .collection('devices')
          .get();
      final fechaduras = querySnapshot.docs
          .map((doc) => doc.data()..['id'] = doc.id)
          .toList();
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
                'isOnline': true, // Start as online by default
              },
            )
            .toList();
        _isLoading = false;
      });

      // Fetch status for all devices
      final backendToken = await LocalService.getBackendToken();
      if (backendToken != null && cartoes.isNotEmpty) {
        try {
          final response = await http.get(
            Uri.parse('${LocalService.backendUrl}/devices'),
            headers: {'Authorization': 'Bearer $backendToken'},
          );
          if (response.statusCode == 200) {
            final devices = jsonDecode(response.body) as List;
            setState(() {
              for (var cartao in cartoes) {
                final device = devices.firstWhere(
                  (d) => d['uuid'] == cartao['id'],
                  orElse: () => null,
                );
                if (device != null) {
                  final lastHeard = device['last_heard'];
                  final isOnline =
                      lastHeard != null &&
                      (DateTime.now().millisecondsSinceEpoch - lastHeard) <
                          30000;
                  final isUnlocked = device['lock_state'] == 'UNLOCKED';
                  final lockedDownAt = device['locked_down_at'];
                  cartao['isOnline'] = isOnline;
                  cartao['isUnlocked'] = isUnlocked;
                  cartao['locked_down_at'] = lockedDownAt;
                } else {
                  cartao['isUnlocked'] = false;
                  cartao['locked_down_at'] = null;
                }
              }
            });
          }
        } catch (e) {
          // ignore
        }
      }

      print('${cartoes.length} fechaduras carregadas');
    } catch (e) {
      print('Erro ao carregar fechaduras: $e');
      setState(() => _isLoading = false);
    }
  }

  Widget _buildEmptyStateHome() {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: EdgeInsets.fromLTRB(20, 40, 20, 40),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blueAccent.withOpacity(0.2),
                  Colors.blueAccent.withOpacity(0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.white54),
                SizedBox(height: 16),
                Text(
                  'Nenhuma fechadura',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Você não possui nenhuma fechadura no momento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    _showAddCardDialog();
                  },
                  icon: Icon(Icons.add, color: Colors.white),
                  label: Text(
                    'Adicionar Fechadura',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent.withOpacity(0.7),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
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

class _ConteudoCartao extends StatelessWidget {
  final String Name;
  final IconData icon;
  final String fechaduraId;
  final bool isLockedDown;
  final bool isOnline;
  final bool isUnlocked;

  const _ConteudoCartao({
    required this.Name,
    required this.icon,
    required this.fechaduraId,
    required this.isLockedDown,
    required this.isOnline,
    required this.isUnlocked,
  });

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

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(Name, style: TextStyle(color: Colors.white)),
                SizedBox(width: 10),
                Icon(icon, color: Colors.white),
              ],
            ),
            if (isLockedDown) ...[
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.security, size: 12, color: Colors.red),
                    SizedBox(width: 4),
                    Text(
                      'Bloqueada',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isOnline && isUnlocked) ...[
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_open, size: 12, color: Colors.green),
                    SizedBox(width: 4),
                    Text(
                      'Aberta',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (!isOnline) ...[
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade800.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.shade800.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.wifi_off,
                      size: 12,
                      color: Colors.orange.shade800,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Desconectada',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
            // Container with Glass Effect
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    height: 68, // Increased height for better alignment
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blueAccent.withOpacity(0.3),
                          Colors.blueAccent.withOpacity(0.1),
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

            // Navigation Items
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
                        widget.onTap(index); // Update selected item
                        Future.delayed(const Duration(milliseconds: 100), () {
                          widget.animateTheIcon(index); // Animate icon
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
                          height: 56, // Maintain height for the container
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
                          child: Center(
                            // Center the icon vertically and horizontally
                            child: SizedBox(
                              height: 36, // Set height for the icon
                              width: 36, // Set width for the icon
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
