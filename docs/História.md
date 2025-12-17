---
title: LockWise — História
subtitle: "Cronologia do desenvolvimento e evolução do projeto"
author: "Amanda Canizela Guimarães, Ariel Inácio Jordão, Felipe Castelo Branco de Mello, Lucca M. A. Pellegrini"
date: 2025-12-16
lang: pt-BR
---

# História

O LockWise foi desenvolvido como trabalho universitário para as disciplinas de
*Projeto Integrado: Desenvolvimento Móvel* e de *Sistemas Embarcados* do curso
de graduação em Engenharia de Computação da Pontifícia Universidade Católica de
Minas Gerais (PUC Minas), unidade Lourdes, no segundo semestre de 2025. Foi
projetado e desenvolvido por Amanda Canizela Guimarães, Ariel Inácio Jordão
Coelho, Felipe Castelo Branco de Mello, e Lucca Mendes Alves Pellegrini, sob a
orientação do professor Ilo Amy Saldanha Rivero.

## Origem do Projeto

Durante as primeiras aulas dessas duas disciplinas, o professor Ilo nos
apresentou as tecnologias que utilizaríamos ao longo do semestre: na aula de
*Projeto Integrado*, apresentou a linguagem de programação
[Dart](https://dart.dev/) e a framework [Flutter](https://flutter.dev/); já
na aula de *Sistemas Embarcados*, nos apresentou o conceito de um [Sistema
Operacional de Tempo
Real](https://pt.wikipedia.org/wiki/Sistema_operacional_de_tempo_real),
mencionando especificamente o [FreeRTOS](https://freertos.org/). Desde o
início dessas aulas, já tínhamos a intenção de fazer o desenvolvimento de um
único projeto semestral para ambas as disciplinas. Com a permissão do
professor, então, decidimos fazer um sistema de fechadura digital com
reconhecimento de voz, já que isso integraria alguns conceitos que já
conhecíamos de disciplinas anteriores — como o [protocolo
MQTT](https://mqtt.org/), a [família de microcontroladores
ESP32](https://www.espressif.com/en/products/modules/esp32), e o SGBD
[PostgreSQL](https://www.postgresql.org/) — com novos aprendizados, incluindo
desenvolvimento móvel, projeto de *back-ends* em contêineres, segurança do
*broker* MQTT, autenticação via *[bearer
tokens](https://datatracker.ietf.org/doc/html/rfc6750)* e *[JSON Web
Tokens](https://www.jwt.io/)*, e, principalmente, programação de
microcontroladores sem o uso das [frameworks e
ferramentas](https://docs.platformio.org/en/latest/frameworks/arduino.html) a
que estávamos acostumados.

## Fases de Desenvolvimento

### Concepção e Planejamento

A concepção inicial era vaga: sabíamos que nosso protótipo final seria algum
tipo de fechadura eletrônica com algum atuador mecânico, fosse ele um
servomotor, um solenoide, ou uma trava magnética. Não tínhamos certeza se o
sistema seria alimentado por bateria ou ligado à tomada, nem se o aplicativo
teria funcionalidades offline. À medida que discutíamos as possibilidades,
optamos por desenvolver um aplicativo que faria pareamento via Bluetooth ao
dispositivo, com os dados armazenados no
[Firebase](https://firebase.google.com/), comunicação feita por meio de um
*broker* MQTT [NanoMQ](https://nanomq.io/) hospedado pelo grupo em um VPS
barato e configurado para fazer [controle de
acesso](https://nanomq.io/docs/en/latest/access-control/introduction.html), e
reconhecimento de voz usando um *back-end* fino, feito em
[Rust](https://rust-lang.org/), [Node/Bun](https://bun.sh/),
[Go](https://go.dev/), ou [Python/FastAPI](https://fastapi.tiangolo.com/). A
fechadura seria controlada por pares de chave privada/pública geradas
bilateralmente pelo dispositivo e pelo aplicativo, com a troca feita por meio
do Firebase. As chaves poderiam ser usadas para autenticar o usuário para a
fechadura usando vários meios, dos quais planejávamos implementar Bluetooth LE,
LAN, e
[NFC-DEP](https://nfc-forum.org/build/specifications/digital-protocol-technical-specification/)/[NDEF](https://gototags.com/help/nfc/ndef),
além do reconhecimento de voz feito no *back-end* usando
[SpeechBrain](https://speechbrain.github.io/). Já no início, o professor Ilo
nos indicou e nos providenciou uma placa de prototipagem [Esp32-LyraT
V4.3](https://docs.espressif.com/projects/esp-adf/en/latest/design-guide/dev-boards/get-started-esp32-lyrat.html),
semelhante aos [DevKits
ESP32](https://www.espressif.com/en/products/devkits/esp32-devkitc) que já
conhecíamos e usávamos desde o primeiro período, mas com várias funções
adicionais para processamento de áudio, incluindo um [chip codec
ES8388](http://www.everest-semi.com/pdf/ES8388%20DS.pdf) integrado, que seria
útil para processar o sinal analógico de áudio sem exigir esforço do
programador.

### Desenvolvimento do Hardware

Durante o desenvolvimento do hardware, nos deparamos com uma variedade de
desafios. O primeiro foi quando percebemos que seria impossível desenvolver
nesse hardware usando a [framework
Arduino](https://docs.platformio.org/en/latest/frameworks/arduino.html), já que
o codec ES8388 não tinha boas bibliotecas implementadas para essa framework.
Nisso, fomos forçados a escolher entre a
[ESP-IDF](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/index.html),
baseada em [FreeRTOS](https://freertos.org/) e desenvolvida pela própria
Espressif, e o sistema operacional
[Zephyr](https://docs.zephyrproject.org/latest/index.html), mas, dado que o
FreeRTOS faz parte da ementa da disciplina, que o Zephyr é relativamente novo,
e que a framework da Espressif também dispõe da [*Espressif Advanced
Development Framework*
(ESP-ADF)](https://docs.espressif.com/projects/esp-adf/en/latest/get-started/),
que poderia ser usada nativamente na placa LyraT, optamos por usar o ESP-IDF
manualmente, sem o intermédio de [outras ferramentas mais
familiares](https://platformio.org/).

O segundo desafio foi a dificuldade de usar um módulo de NFC
[PN532](https://www.elechouse.com/elechouse/images/product/PN532_module_V3/PN532_%20Manual_V3.pdf),
que também foi providenciado pelo professor, mas que não respondia bem aos
comandos enviados via [I²C](https://www.ti.com/lit/pdf/sbaa565). Tentamos
várias abordagens e tentamos integrar várias bibliotecas já existentes, mas
nenhuma funcionou: o dispositivo parecia não responder aos comandos dentro do
tempo limite, causando *timeouts* e outros erros a tempo de execução. Em nenhum
momento conseguimos fazer uma leitura de uma *tag* NFC. Por causa disso,
ocasionou-se o terceiro desafio: já que comunicação via NDEF seria impossível,
faríamos o pareamento e o controle local pelo aplicativo usando Bluetooth LE.
Mas, nessa fase do desenvolvimento, já havíamos implementado a maioria do
código embarcado, incluindo todo o código de controle via MQTT e porta serial,
criptografia em trânsito via
[TLS](https://www.cloudflare.com/learning/ssl/transport-layer-security-tls/)
com [Mbed
TLS](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/protocols/mbedtls.html),
configurações salvas em [armazenamento
não-volátil](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/storage/nvs_flash.html),
e a [API *Periph Wi-Fi* da
Espressif](https://docs.espressif.com/projects/esp-adf/en/latest/api-reference/peripherals/periph_wifi.html),
que é a API de alto nível para conectar a uma rede Wi-Fi. Por causa disso, não
sobrava memória na [*Data RAM*
(DRAM)](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/memory-types.html#dram-data-ram),
por mais que tentássemos minimizar o uso da memória [de outras
formas](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/performance/ram-usage.html),
para as alocações que a [API de
Bluetooth](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/bluetooth/index.html)
faria. Assim, optamos por fazer o pareamento local usando a API Wi-Fi de baixo
nível — a [ESP
Wi-Fi](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/network/esp_wifi.html)
— para criar um ponto de acesso ao qual o smartphone do usuário poderia se
conectar para enviar suas credenciais.

O quarto e último desafio ocorreu quando fizemos o primeiro depoimento do nosso
*back-end* [Rocket](https://rocket.rs/) na nuvem, usando uma imagem gerada
pelo [Podman](https://podman.io/) e executado pelo
[Docker](https://www.docker.com/) atrás de um proxy reverso
[OpenResty](https://openresty.org/en/): até então, todo o desenvolvimento do
*back-end* principal foi feito usando o comando `cargo run` localmente, sem
TLS, e sem nenhum proxy reverso, com o dispositivo enviando dados via HTTP
usando [`Transfer-Encoding:
chunked`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Transfer-Encoding),
o que permitia que o *back-end* recebesse a amostra de áudio por *streaming*,
mas sem exigir que threads independentes se comunicassem com exclusão mútua ou
com semáforos para acessar o buffer de áudio — isso garantia que não
precisaríamos alocar memória para armazenar quantidades abundantes de áudio
codificado, pois seria enviado em tempo real. Infelizmente, o cabeçalho
`Transfer-Encoding` já é raramente suportado, e, por razões que nunca
conseguimos esclarecer totalmente, o proxy reverso no nosso VPS cortava a
transmissão de áudio cedo sempre que ele era usado. Assim, tivemos que
abandonar o *streaming* de áudio e pré-alocar um *buffer* de tamanho fixo para
armazenar todas as amostras obtidas do codec ES8388 durante uma verificação e,
por isso, tivemos que limitar a duração máxima da verificação de voz. Mesmo
assim, em raras ocasiões a DRAM se encontrava muito fragmentada, e falhas de
alocação começaram a ocorrer. Ao examinar um *FAQ* na documentação da
Espressif, percebemos que seria possível [mover o componente Mbed
TLS](https://docs.espressif.com/projects/esp-faq/en/latest/software-framework/protocols/mbedtls.html#when-i-connected-an-esp32-module-with-the-https-server-i-got-the-following-log-what-is-the-reason)
para a [memória externa
SPI](https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/api-guides/flash_psram_config.html),
que a placa LyraT V4.3 felizmente tem integrada, usando o
[`menuconfig`](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/kconfig/project-configuration-guide.html),
o que foi suficiente para que pudéssemos fazer gravações de até *dezenas* de
segundos a 44,1kHz. Percebemos que isso nos permitiria tentar a implementação
de Bluetooth LE novamente, mas com o pareamento por AP Wi-Fi já implementado e
documentado, e com a data de entrega se aproximando, preferimos focar nos
outros componentes do projeto.

### Desenvolvimento do Back-end

####  Back-end principal

#### Sistema de reconhecimento de voz


### Desenvolvimento do Aplicativo
