/* WiFi Management Header */

#pragma once
#ifndef WIFI_H
#define WIFI_H

/**
 * @brief Inicializa a conectividade Wi-Fi em modo station (STA).
 *
 * Esta função configura e conecta o dispositivo à rede Wi-Fi usando as credenciais
 * armazenadas na configuração (SSID e senha).
 *
 * @warning Não chame wifi_init() e wifi_init_ap() dentro do mesmo boot, pois cada uma
 * usa uma abstração diferente e isso pode deixar o módulo Wi-Fi em um estado inválido.
 */
void wifi_init(void);

/**
 * @brief Inicia o servidor de pareamento Wi-Fi em modo Access Point (AP).
 *
 * Esta função configura o dispositivo como um ponto de acesso Wi-Fi para permitir
 * configuração inicial via aplicativo móvel.
 */
void start_pairing_server(void);

#endif /* WIFI_H */
