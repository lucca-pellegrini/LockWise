/* System Utilities Header */
#pragma once

#ifndef SYSTEM_UTILS_H
#define SYSTEM_UTILS_H

/**
 * @brief Para o sistema permanentemente (lockdown).
 *
 * Esta função tranca a fechadura, desconecta MQTT e Wi-Fi, e entra em deep sleep permanente.
 * Usada para bloqueio de emergência do sistema.
 */
void cleanup_halt(void);

/**
 * @brief Reinicializa o sistema.
 *
 * Esta função tranca a fechadura, desconecta MQTT e Wi-Fi, e reinicializa o dispositivo.
 * Publica status de "RESTARTING" via MQTT antes da reinicialização.
 */
void cleanup_restart(void);

#endif /* SYSTEM_UTILS_H */
