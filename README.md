---
title: LockWise
subtitle: "Sistema de fechadura inteligente com autenticação por voz, controle MQTT e aplicativo móvel"
author: "Amanda Canizela Guimarães, Ariel Inácio Jordão, Felipe Castelo Branco de Mello, Lucca M. A. Pellegrini"
date: 2025-12-16
lang: pt-BR
---

# LockWise

Sistema de fechadura inteligente que combina autenticação por voz, controle
remoto via MQTT e uma interface móvel intuitiva, construído para proporcionar
segurança e conveniência modernas.

## Visão Geral

LockWise é uma solução completa para controle de acesso residencial, composta
por três componentes principais:

- **Aplicativo Móvel**: Interface de usuário para gerenciamento e controle remoto
- **Back-end**: Serviços de API, autenticação e processamento de voz
- **Sistema Embarcado**: Hardware da fechadura com processamento de áudio e conectividade

## Componentes

### [Aplicativo Móvel](app/)

Painel de controle móvel construído com Flutter para Android.

- [Funcionalidades](app/README.md#funcionalidades)
- [Pré-requisitos](app/README.md#pré-requisitos)
- [Instalação e Execução](app/README.md#compilação-e-execução)

### [Back-end](backend/)

Serviços de back-end em Rust (Rocket) e Python (FastAPI) para reconhecimento de voz.

- [Funcionalidades](backend/README.md#funcionalidades)
- [Pré-requisitos](backend/README.md#pré-requisitos)
- [Execução](backend/README.md#compilação-e-execução)

### [Sistema Embarcado](embedded/)

Firmware para ESP32-LyraT v4.3 com autenticação por voz e controle via MQTT.

- [Funcionalidades](embedded/README.md#funcionalidades)
- [Pré-requisitos](embedded/README.md#pré-requisitos)
- [Compilação e Gravação](embedded/README.md#compilação-e-gravação)

## Começando

1. **Configure o Back-end**: Siga as instruções em
   [backend/README.md](backend/README.md) para executar os serviços de API e
   reconhecimento de voz.

2. **Prepare o Sistema Embarcado**: Compile e grave o firmware conforme
   [embedded/README.md](embedded/README.md).

3. **Instale o Aplicativo**: Configure e execute o aplicativo móvel seguindo
   [app/README.md](app/README.md).

4. **Pareamento Inicial**: Use o modo de pareamento do dispositivo para
   conectar ao aplicativo.

## Arquitetura

O sistema utiliza uma arquitetura distribuída:

- **Comunicação**: MQTT para controle em tempo real entre dispositivos
- **Autenticação**: Firebase para usuários, reconhecimento de voz via SpeechBrain
- **Armazenamento**: PostgreSQL para dados persistentes
- **Processamento de Áudio**: Captura e análise em tempo real no dispositivo embarcado

## Licença

Este projeto é composto por múltiplos componentes, cada um com sua própria licença:

- [Aplicativo Móvel](app/README.md#licença)
- [Back-end](backend/README.md#licença)
- [Sistema Embarcado](embedded/README.md#licença)
