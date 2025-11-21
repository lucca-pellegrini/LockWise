/* Audio Streaming Header */

#ifndef AUDIO_STREAM_H
#define AUDIO_STREAM_H

#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

// Commands for audio streaming
typedef enum { AUDIO_STREAM_START, AUDIO_STREAM_STOP } audio_stream_cmd_t;

// Function to initialize audio streaming task
void audio_stream_init(void);

// Function to send command to audio stream task
void audio_stream_send_cmd(audio_stream_cmd_t cmd);

#endif // AUDIO_STREAM_H