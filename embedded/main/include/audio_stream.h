/* Audio Streaming Header */

#ifndef AUDIO_STREAM_H
#define AUDIO_STREAM_H

#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

/**
 * @brief Comandos para controle do streaming de áudio.
 *
 * Este enum define os comandos disponíveis para iniciar ou parar o streaming de áudio.
 */
typedef enum {
	AUDIO_STREAM_START, /**< Inicia o streaming de áudio */
	AUDIO_STREAM_STOP /**< Para o streaming de áudio */
} audio_stream_cmd_t;

/**
 * @brief Inicializa a tarefa de streaming de áudio.
 *
 * Esta função configura o pipeline de áudio, inicializa as tarefas de VAD (Voice Activity Detection)
 * e streaming HTTP, além de criar as filas e semáforos necessários para o gerenciamento do áudio.
 */
void audio_stream_init(void);

/**
 * @brief Envia um comando para a tarefa de streaming de áudio.
 *
 * @param cmd Comando a ser enviado (AUDIO_STREAM_START ou AUDIO_STREAM_STOP).
 */
void audio_stream_send_cmd(audio_stream_cmd_t cmd);

#endif // AUDIO_STREAM_H
