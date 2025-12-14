---
title: LockWise — Aplicativo Móvel
subtitle: "Um painel de controle para seus produtos LockWise"
author: "Amanda Canizela, Ariel Inácio, Lucca M. A. Pellegrini"
date: 2025-12-13
lang: pt-BR
---

# LockWise — Aplicativo Móvel

Um painel de controle para seus produtos LockWise, construído com [Flutter](https://flutter.dev/) para
[Android](https://developer.android.com/).

## Funcionalidades

- **Autenticação de Usuário**: Login e cadastro com *Firebase Authentication*
- **Gerenciamento de Fechaduras**: Adicione, remova e controle suas fechaduras
  inteligentes
- **Controle Remoto**: Tranque e destranque portas remotamente via MQTT
- **Autenticação por Voz**: Desbloqueie suas fechaduras usando reconhecimento de voz
- **Compartilhamento de Acesso**: Convide familiares e amigos para acessar suas
  fechaduras
- **Notificações em Tempo Real**: Receba alerta sobre acessos e estado das
  fechaduras
- **Histórico de Acessos**: Visualize logs detalhados de todas as operações
- **Configurações Avançadas**: Personalize Wi-Fi, tempos de gravação e bloqueio
- **Modo de Bloqueio de Emergência**: Ative bloqueio físico para máxima segurança
- **Interface Intuitiva**: Design *glassmorphism* com animações suaves

## Requisitos de Hardware

- **Dispositivo Android** (API 21+)
- **Conectividade Wi-Fi** para comunicação com fechaduras
- **Permissões**: Localização (para Wi-Fi), notificações

Para detalhes sobre o hardware das fechaduras, consulte [../embedded/README.md](../embedded/README.md).

## Pré-requisitos

### [Flutter](https://flutter.dev/) SDK
Certifique-se de que o Flutter está instalado e configurado:

```bash
flutter doctor
```

### Firebase
Configure o Firebase para o projeto:
1. Crie um projeto no [Firebase Console](https://console.firebase.google.com/)
2. Adicione aplicativo Android e habilite *Firestore Database* e *Firebase
   Authenticaton* com e-mail/senha
3. Instale o [Firebase
   CLI](https://firebase.google.com/docs/cli#setup_update_cli)
4. Ative a ferramenta com `dart pub global activate flutterfire_cli`
5. Configure o projeto local com `flutterfire configure`

### Dependências
Instale as dependências do projeto:

```bash
flutter pub get
```

## Estrutura do Projeto

```
app/
├── lib/
│   ├── main.dart                    # Ponto de entrada da aplicação
│   ├── PaginaBoasVindas.dart        # Tela de onboarding
│   ├── PaginaLogin.dart             # Tela de login
│   ├── PaginaCadastro.dart          # Tela de cadastro
│   ├── PaginaInicial.dart           # Tela principal com fechaduras
│   ├── PaginaDetalhe.dart           # Detalhes e controle de fechadura
│   ├── PaginaNotificação.dart       # Histórico de notificações
│   ├── PaginaConfig.dart            # Configurações do app
│   ├── PaginaConta.dart             # Gerenciamento de conta
│   ├── PaginaConvite.dart           # Gerenciamento de convites
│   ├── PaginaSobre.dart             # Sobre o app
│   ├── PaginaEsqueci.dart           # Recuperação de senha
│   ├── PaginaNovaSenha.dart         # Alteração de senha
│   ├── PaginaTemporaria.dart        # Acessos temporários
│   ├── LocalService.dart             # Serviços locais (auth, storage)
│   ├── models/
│   │   ├── AssetPreloader.dart      # Pré-carregamento de assets
│   │   ├── nav_item_model.dart      # Modelo de navegação
│   │   └── rive_model.dart          # Modelo Rive animations
│   └── firebase_options.dart        # Configurações Firebase (arquivo com segredos)
├── android/                         # Configurações Android
├── assets/                          # Assets (fonts, images)
├── pubspec.yaml                     # Dependências e configuração
└── README.md                        # Este arquivo
```

## Configuração

### 1. Configuração do Firebase
1. Copie `google-services.json` para `android/app/`
2. Copie `GoogleService-Info.plist` para `ios/Runner/`
3. Configure as regras do Firestore para permitir acesso autenticado

### 2. Configuração do Back-end
Copie `.env.example` para `.env` e atualize a URL do back-end:

```bash
cp .env.example .env
```

Edite `.env` para definir a URL correta:

```
BACKEND_URL=https://seu-backend-url
```

**Nota:** A aplicação falhará ao iniciar sem o arquivo `.env` configurado.

### 3. Configuração de Assets
Certifique-se de que as imagens estão em `assets/images/` e referenciadas no
`pubspec.yaml`.

## Compilação e Execução

### Desenvolvimento
```bash
# Executar no dispositivo/emulador
flutter run

# Executar com hot reload
flutter run --hot
```

### Build de Produção
```bash
# Android APK
flutter build apk --release

# Android AAB
flutter build appbundle --release
```

### Testes
```bash
# Executar testes
flutter test

# Verificar linting
flutter analyze
```

## Modo de Pareamento

Para adicionar uma nova fechadura:

1. Toque no sensor de pareamento da fechadura (TOUCH_PAD_NUM9)
2. Dispositivo entra em modo AP Wi-Fi (`LockWise-<id>`)
3. Conecte-se à rede Wi-Fi da fechadura
4. Use o app para configurar Wi-Fi e parear
5. Fechadura reinicia e aparece no painel

## Solução de Problemas

### Problemas de Conectividade
- Verifique se o back-end está rodando na URL configurada
- Confirme permissões de Wi-Fi no dispositivo
- Teste conectividade com `ping SEU_BACKEND_IP`

### Erros de Firebase
- Verifique se `google-services.json` está correto
- Confirme regras do Firestore permitem leitura/escrita autenticada
- Teste autenticação no Firebase Console

### Problemas de Build
- Execute `flutter clean` e `flutter pub get`
- Verifique versão do Flutter: `flutter --version`
- Atualize dependências: `flutter pub upgrade`

### Fechadura Não Responde
- Verifique se fechadura está online (ícone verde)
- Confirme conectividade MQTT
- Teste ping manualmente via back-end

## Dicas de Desenvolvimento

1. **Gerenciamento de Versão Flutter**: Este projeto usa FVM (Flutter Version
   Management) de <https://fvm.app/> para gerenciar versões do Flutter. Use
   `fvm use` para ativar a versão correta.
2. **Comece Simples**: Teste autenticação primeiro, depois funcionalidades
   básicas
3. **Use Hot Reload**: Aproveite o hot reload do Flutter para iterações rápidas
4. **Debug Networking**: Use ferramentas como Charles Proxy para inspecionar
   requests
5. **Teste em Dispositivos Reais**: Emuladores podem não refletir comportamento
   real de Wi-Fi
6. **Gerencie Estado**: Use streams para atualizações em tempo real dos
   dispositivos
7. **Otimize Assets**: Pré-carregue imagens pesadas para melhor UX

## Licença

Este projeto é licenciado sob [Apache License 2.0](LICENSE).
