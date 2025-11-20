/* Audio Management Header */

#ifndef AUDIO_H
#define AUDIO_H

#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

/* Audio configuration */
#define AUDIO_SAMPLE_RATE 16000
#define AUDIO_BITS 16
#define AUDIO_CHANNELS 1
#define RECORD_DURATION_MS 3000 // 3 seconds for voice sample

/* Audio buffer for recording */
extern uint8_t *audio_buffer;
extern size_t audio_buffer_len;

/* Function prototypes */
void audio_pipeline_setup(void);
esp_err_t start_voice_recording(void);

#endif /* AUDIO_H */