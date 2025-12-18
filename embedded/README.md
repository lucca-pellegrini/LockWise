---
title: LockWise — Sistema Embarcado
subtitle: "Um sistema de fechadura inteligente controlado por autenticação de voz e comandos MQTT, construído para ESP32-LyraT v4.3 usando ESP-IDF e ESP-ADF."
author:
    - Felipe Castelo Branco de Mello
    - Lucca M. A. Pellegrini
date: 2025-12-13
lang: pt-BR
---

# LockWise — Sistema Embarcado

Um sistema de fechadura inteligente controlado por autenticação de voz e
comandos [MQTT](https://mqtt.org/), construído para [ESP32-LyraT](https://docs.espressif.com/projects/esp-adf/en/latest/design-guide/dev-boards/get-started-esp32-lyrat.html) v4.3 usando [ESP-IDF](https://docs.espressif.com/projects/esp-idf/en/stable/) e [ESP-ADF](https://docs.espressif.com/projects/esp-adf/en/latest/).

## Funcionalidades

- **Autenticação por Voz**: Grava amostras de áudio e as verifica contra a API
  do back-end
- **Controle Remoto via MQTT**: Destranca/tranca via aplicativo móvel por
  broker MQTT
- **Trancamento Automático**: Tranca automaticamente após um tempo configurável
- **Armazenamento Persistente**: Credenciais Wi-Fi e configuração do dispositivo
  armazenadas em flash (Non-Volatile Storage)
- **Processamento de Áudio**: Utiliza microfones de alta qualidade do
  ESP32-LyraT com codec de áudio hardware
- **Controle por Toque**: Sensores de toque para controle manual e modo de
  pareamento
- **Modo de Pareamento**: Servidor Wi-Fi AP para configuração inicial
- **Heartbeat MQTT**: Publicação periódica de estado e configuração

## Requisitos de Hardware

- **Placa de desenvolvimento ESP32-LyraT** (versão 4.3 ou compatível)
- **Mecanismo de fechadura** (solenoide, servo ou fechadura eletrônica)
- **Controle GPIO** para atuação da fechadura
- **Sensores de toque** (integrados na ESP32-LyraT para controle manual)

## Pré-requisitos

O projeto usa submódulos Git para [ESP-ADF](https://docs.espressif.com/projects/esp-adf/en/latest/), que já inclui [ESP-IDF](https://docs.espressif.com/projects/esp-idf/en/stable/). Certifique-se
de que os submódulos estão inicializados e habilitados:

```bash
git submodule update --init --recursive
./embedded/esp-adf/install.sh
. ./embedded/esp-adf/export.sh
```

## Estrutura do Projeto

O projeto está organizado da seguinte forma:

- **main/**: Código principal da aplicação
  - **src/**: Arquivos fonte C
    - [main.c](main/src/main.c): Ponto de entrada e inicialização do sistema
    - [lock.c](main/src/lock.c): Controle da fechadura e atuadores
    - [audio_stream.c](main/src/audio_stream.c): Streaming de áudio para autenticação por voz
    - [mqtt.c](main/src/mqtt.c): Gerenciamento de conexões MQTT
    - [wifi.c](main/src/wifi.c): Conectividade Wi-Fi e modo de pareamento
    - [config.c](main/src/config.c): Gerenciamento de configuração e NVS
    - [serial.c](main/src/serial.c): Comandos via interface serial
    - [system_utils.c](main/src/system_utils.c): Utilitários de sistema (reinicialização, halt)
  - **include/**: Arquivos de cabeçalho
  - [CMakeLists.txt](main/CMakeLists.txt): Configuração do build para o componente main
  - [Kconfig.projbuild](main/Kconfig.projbuild): Opções de configuração específicas do projeto
- **esp-adf/**: Submódulo do framework ESP-ADF
- [CMakeLists.txt](CMakeLists.txt): Configuração principal do build
- [partitions.csv](partitions.csv): Definição das partições da flash
- [sdkconfig.defaults](sdkconfig.defaults): Configurações padrão do ESP-IDF
- [LICENSE](LICENSE): Licença do projeto
- [README.md](README.md): Este arquivo

## Configuração

### 1. Configuração Básica via *menuconfig*

```bash
cd embedded
./build.sh menuconfig
```

Navegue até **"LockWise Configuration"** e defina:

- **Wi-Fi SSID**: Nome da rede Wi-Fi
- **Wi-Fi Password**: Senha da rede Wi-Fi
- **Device ID**: Identificador único (UUID válido, ex.:
  `a66c566e-b40d-4136-8965-cf990b510fae`)
- **Backend URL**: URL do back-end para streaming de áudio
- **MQTT Broker URL**: URL do broker MQTT
- **Lock Actuator GPIO**: Pino GPIO para controle da fechadura (ou −1 para
  desabilitar durante desenvolvimento)

### 2. Configuração em Tempo de Execução (via Non-Volatile Storage)

O dispositivo armazena configuração em flash NVS. Você pode atualizar estes
valores programaticamente ou via interface de configuração:

- `wifi_ssid`: Nome da rede Wi-Fi
- `wifi_pass`: Senha da rede Wi-Fi
- `device_id`: Identificador único do dispositivo
- `backend_url`: URL da API back-end
- `mqtt_broker_url`: URL do broker MQTT
- `mqtt_broker_password`: Senha do broker MQTT
- `backend_bearer_token`: Token de autenticação para API
- `lock_timeout_ms`: Tempo para trancamento automático (ms)
- `audio_record_timeout_sec`: Tempo limite de gravação de áudio (s)
- `pairing_timeout_sec`: Tempo limite do modo de pareamento (s)

## Compilação e Gravação

```bash
## Compilar o projeto
./build.sh build

## Gravar no dispositivo (conectar via USB)
./build.sh flash /dev/ttyUSB0

## Monitorar saída serial
./build.sh monitor /dev/ttyUSB0

## Ou fazer tudo em sequência: build, flash e monitor
./build.sh all /dev/ttyUSB0
```

Para sair do monitor serial, pressione `Ctrl+]`.

## Configuração de GPIO

### Pinos Usados na ESP32-LyraT v4.3

**Usados pelo Sistema de Áudio**:
- Pinos I²S (BCLK, WS, DOUT, DIN) — usados pelo codec de áudio
- Pinos I²C (GPIO18, GPIO23) — usados para controle do codec

**Pinos de Controle da Fechadura**:
- GPIO configurável (padrão: definido em [Kconfig](main/Kconfig.projbuild))
  para atuador da fechadura
- GPIO33 (TOUCH_PAD_NUM8) — sensor de toque para destrancar
- GPIO32 (TOUCH_PAD_NUM9) — sensor de toque para modo de pareamento

**LED Indicador**:
- GPIO fixo para LED de status (piscando durante inicialização, acesso, etc.)

## Modo de Pareamento

O dispositivo suporta modo de pareamento para configuração inicial:

1. Toque no sensor de pareamento (TOUCH_PAD_NUM9)
2. Dispositivo reinicia em modo AP Wi-Fi, e o LED integrado piscará brevemente a
   cada segundo
3. Conecte seu dispositivo móvel à rede `LockWise-<id_único>` usando a senha
   indicada na fechadura, e use o aplicativo para associar sua conta ao
    dispositivo e configurar a rede Wi-Fi
4. O dispositivo reiniciará automaticamente, e aparecerá na aba *Minhas
   LockWise* no seu aplicativo

## Solução de Problemas

### Áudio Não Está Gravando
- Verifique se os pinos I²S não estão em conflito
- Confirme inicialização do quadro de áudio: `audio_board_init()`
- Monitore logs para erros do codec

### Conexão Wi-Fi Falhou
- Verifique SSID e senha no *menuconfig* ou NVS
- Verifique força do sinal Wi-Fi
- Certifique-se de que Wi-Fi é 2.4GHz (ESP32 não suporta 5GHz)

### MQTT Não Conectando
- Verifique formato da URL do broker: `mqtt://broker.example.com:1883` ou
  `mqtts://`
- Verifique configurações de firewall/rede
- Certifique-se de que o broker permite conexões anônimas (ou adicione
  credenciais)

### Fechadura Não Respondendo
- Se usando GPIO: Verifique se o pino não é usado por outros periféricos
- Teste com multímetro: Meça tensão no pino de controle

## Dicas de Desenvolvimento

1. **Comece Simples**: Teste cada componente individualmente
   - Conexão Wi-Fi primeiro
   - Streaming de áudio
   - Requisições HTTP
   - MQTT separadamente
   - Controle da fechadura

2. **Use Monitor Serial**: Use o script [build.sh](build.sh) para monitorar:
   ```bash
   ./build.sh monitor /dev/ttyUSB0
   ```

3. **Ajuste Níveis de Log**: Em [cada componente](main/src/), ajuste:
   ```c
   esp_log_level_set(TAG, ESP_LOG_DEBUG);
   ```

4. **Gerência de Memória**: ESP32 tem RAM limitada
   - Use PSRAM se disponível (habilitado em *menuconfig*)
   - Libere buffers após uso
   - Monitore uso de heap: `esp_get_free_heap_size()`

## Documentação

Documentação técnica autogerada do código C está disponível
[aqui](https://lockwise-docs.verticordia.com/embedded/). A seção relevante do
relatório técnico está [aqui](../docs/Embedded.md).

## Licença

Este projeto é licenciado sob [Apache License 2.0](LICENSE).
