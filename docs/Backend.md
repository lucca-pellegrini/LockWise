---
title: LockWise — Back-End
subtitle: "Documentação técnica do componente back-end"
author: "Amanda Canizela Guimarães, Ariel Inácio Jordão, Felipe Castelo Branco de Mello, Lucca M. A. Pellegrini"
date: 2025-12-16
lang: pt-BR
---

# Desenvolvimento do Back-End

## História

Inicialmente, planejávamos não escrever um *back-end*, mas usar o
[Firebase](https://firebase.google.com/) para toda a comunicação remota entre
o aplicativo e o dispositivo, usando as funcionalidades integradas da
plataforma para comunicação via MQTT. Infelizmente, com a deprecação do serviço
de reconhecimento de voz que originalmente planejamos usar, ficou claro que
teríamos que implementar um *back-end*, nem que mínimo, para calcular os
[*embeddings* ECAPA-TDNN](https://arxiv.org/abs/2104.01466) que usaríamos
para fazer a diarização da voz — como descrevemos abaixo — e, assim,
identificar sem ambiguidade quem é o locutor. O plano inicial, então, era fazer
um único componente para o *back-end:* um serviço simples em Python, usando
[SpeechBrain](https://speechbrain.github.io/) e alguma framework web leve,
para controlar tanto o reconhecimento de voz quanto as funcionalidades do
aplicativo que exigissem mais segurança que o plano gratuito do Firebase é
capaz de providenciar. Eventualmente, essa ideia foi descartada pela
dificuldade que teríamos de dividir as tarefas, e pela dificuldade de escrever
um *back-end* robusto e com desempenho decente nessa linguagem — decidimos
dividir o *back-end* em dois serviços: um *back-end “principal”*, e um serviço
isolado em Python para a diarização.


##  Back-End *Rocket*

### Visão Geral

### Detalhes de Implementação

## Serviço de *Speaker Recognition*

### Visão Geral

#### Escolha da Stack

A solução implementada utiliza Python como linguagem de programação principal,
combinada com as bibliotecas [PyTorch](https://pytorch.org/) e
[SpeechBrain](https://speechbrain.github.io/). Esta escolha se justifica por
diversos fatores técnicos e práticos. O Python oferece um ecossistema maduro e
bem estabelecido para aplicações de aprendizado de máquina, com ampla
documentação e suporte da comunidade. O PyTorch, por sua vez, representa o
estado da arte em frameworks de aprendizado profundo, e proporciona
flexibilidade na manipulação de tensores e operações em GPU quando necessário.
A biblioteca SpeechBrain foi selecionada especificamente por fornecer modelos
pré-treinados de alta qualidade para tarefas de processamento de áudio e fala,
eliminando a necessidade de treinamento do zero e garantindo resultados
consistentes e academicamente validados.

#### Modelo Utilizado

O modelo escolhido foi o
[`spkrec-ecapa-voxceleb`](https://huggingface.co/speechbrain/spkrec-ecapa-voxceleb)
disponibilizado pelo SpeechBrain. Trata-se de uma implementação da arquitetura
[ECAPA-TDNN *(Emphasized Channel Attention, Propagation and Aggregation in
Time Delay Neural Network)*](https://arxiv.org/abs/2104.01466), treinada na
base de dados [VoxCeleb](https://www.robots.ox.ac.uk/~vgg/data/voxceleb/),
que contém milhares de horas de gravações de fala de diversos locutores em
condições variadas. A seleção deste modelo se fundamenta em seu desempenho
comprovado em tarefas de verificação e identificação de locutor, com taxa de
erro significativamente reduzida em comparação com arquiteturas anteriores. A
arquitetura ECAPA-TDNN incorpora mecanismos de atenção que permitem ao modelo
focar nas características mais discriminativas da voz, resultando em
*embeddings* mais robustos e distintivos para cada locutor.

#### Funcionamento do Modelo

O modelo opera transformando amostras de áudio bruto em representações
vetoriais de dimensão fixa. O processamento inicia com a conversão do áudio PCM
de 16 bits em formato de waveform normalizado, seguido de reamostragem para
16kHz quando necessário, frequência na qual o modelo foi treinado. A
arquitetura ECAPA-TDNN processa então este sinal através de múltiplas camadas
convolucionais temporais (TDNN), que extraem características acústicas em
diferentes escalas temporais. Os blocos de atenção de canal enfatizam as
características mais relevantes para identificação do locutor, enquanto camadas
de pooling estatístico agregam informações ao longo de toda a duração do áudio.
O resultado final é um vetor de *embedding* de 192 dimensões que encapsula as
características biométricas vocais únicas do locutor. Este vetor é normalizado
para ter norma unitária, garantindo que comparações posteriores se baseiem
exclusivamente na direção do vetor no espaço de características, não em sua
magnitude.

#### Armazenamento e Comparação de *Embeddings*

Os vetores de 192 dimensões gerados pelo modelo são serializados em formato
*base64* para transmissão eficiente. Esta representação compacta permite que os
*embeddings* sejam facilmente transmitidos por APIs REST. Para a tarefa de
verificação de locutor, o sistema calcula a similaridade de cossenos entre o
*embedding* da amostra de teste e os *embeddings* armazenados dos locutores
conhecidos. A similaridade de cossenos mede o ângulo entre dois vetores no
espaço de 192 dimensões, produzindo um valor entre −1 e 1, onde valores
próximos a 1 indicam alta similaridade entre as vozes. Devido à normalização
dos *embeddings*, esta métrica se torna equivalente ao produto escalar entre os
vetores, o que constitui uma implementação computacionalmente eficiente. O
locutor identificado é aquele cujo *embedding* armazenado apresenta a maior
similaridade com a amostra de teste, com o valor de score fornecendo uma medida
de confiança na identificação.

### Detalhes de Implementação
