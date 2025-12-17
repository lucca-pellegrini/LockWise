---
title: LockWise — Introdução
subtitle: "Visão geral completa do sistema LockWise e seus componentes"
author: "Amanda Canizela Guimarães, Ariel Inácio Jordão, Felipe Castelo Branco de Mello, Lucca M. A. Pellegrini"
date: 2025-12-16
lang: pt-BR
---

[Próximo: História →](História.md)

# Introdução ao LockWise

O LockWise é um sistema completo de fechadura inteligente que combina
autenticação por voz, e uma interface móvel intuitiva. Desenvolvido para
proporcionar segurança e conveniência, o sistema consiste de três componentes:
aplicativo móvel, back-end, e sistema embarcado.

## Visão Geral

O LockWise oferece uma solução abrangente para controle de acesso residencial e
comercial. O sistema opta por uma abordagem de autenticação multifatorial, que
combina reconhecimento de voz processado na nuvem via
[SpeechBrain](https://speechbrain.github.io/), controles por toque capacitivo
para acesso local, e opções de controle remoto direto pelo aplicativo.
Utilizando comunicação [MQTT](https://mqtt.org/) para baixa latência, o
LockWise garante operações em tempo real entre todos os componentes.

Além disso, a gerência remota é facilitado por uma interface móvel intuitiva
que permite controle completo das fechaduras de qualquer lugar. O
compartilhamento seguro de acesso é implementado por um sistema de convites
temporários. O monitoramento contínuo inclui logs detalhados, notificações push
e heartbeat [MQTT](https://mqtt.org/) para manter o usuário informado sobre
os estados dos dispositivos. Além disso, destaca-se o processamento seguro de
reconhecimento de voz na nuvem, com transmissão de áudio do dispositivo
embarcado, preservando a privacidade dos usuários. Nenhuma amostra de áudio é
armazenada em nenhum momento, nem temporariamente: o áudio dos usuários nunca é
colocado em disco, para garantir a privacidade e impossibilitar *replay
attacks*.

[Próximo: História →](História.md)