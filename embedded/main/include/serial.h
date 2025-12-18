/* Serial Command Header */

#pragma once
#ifndef SERIAL_H
#define SERIAL_H

/**
 * @brief Tarefa para processar comandos recebidos via interface serial.
 *
 * @param pvParameters Parâmetros da tarefa (não usado).
 *
 * Esta tarefa lê comandos da UART (porta serial) e executa ações correspondentes,
 * como atualizar configuração, trancar/destrancar porta ou reinicializar o dispositivo.
 * Comandos suportados incluem: update_config, unlock, lock, record, stop, reboot, lockdown, flash, pair.
 */
void serial_command_task(void *pvParameters);

#endif /* SERIAL_H */
