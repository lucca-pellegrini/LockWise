/* Audio Management Implementation */

#include "audio.h"
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "audio_event_iface.h"
#include "audio_common.h"
#include "audio_pipeline.h"
#include "board.h"
#include "i2s_stream.h"
#include "raw_stream.h"
#include "audio_idf_version.h"

static const char *TAG = "LOCKWISE_AUDIO";

/* Audio buffer for recording */
#define AUDIO_BUFFER_SIZE (AUDIO_SAMPLE_RATE * AUDIO_CHANNELS * (AUDIO_BITS / 8) * (RECORD_DURATION_MS / 1000))
uint8_t *audio_buffer = NULL;
size_t audio_buffer_len = 0;

/* Global audio pipeline handles */
static audio_pipeline_handle_t pipeline;
static audio_element_handle_t i2s_reader, raw_writer;

void audio_pipeline_setup(void)
{
	ESP_LOGI(TAG, "Initializing audio pipeline");

	// Initialize audio board
	audio_board_handle_t board_handle = audio_board_init();
	audio_hal_ctrl_codec(board_handle->audio_hal, AUDIO_HAL_CODEC_MODE_ENCODE, AUDIO_HAL_CTRL_START);

	// Create pipeline
	audio_pipeline_cfg_t pipeline_cfg = DEFAULT_AUDIO_PIPELINE_CONFIG();
	pipeline = audio_pipeline_init(&pipeline_cfg);

	// Create I2S stream reader (from microphones)
	i2s_stream_cfg_t i2s_cfg = I2S_STREAM_CFG_DEFAULT();
	i2s_cfg.type = AUDIO_STREAM_READER;

#if (ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 0, 0))
	i2s_cfg.chan_cfg.id = CODEC_ADC_I2S_PORT;
	i2s_cfg.std_cfg.slot_cfg.slot_mode = I2S_SLOT_MODE_MONO;
	i2s_cfg.std_cfg.slot_cfg.slot_mask = I2S_STD_SLOT_LEFT;
	i2s_cfg.std_cfg.clk_cfg.sample_rate_hz = AUDIO_SAMPLE_RATE;
#else
	i2s_cfg.i2s_port = CODEC_ADC_I2S_PORT;
	i2s_cfg.i2s_config.channel_format = I2S_CHANNEL_FMT_ONLY_LEFT;
	i2s_cfg.i2s_config.sample_rate = AUDIO_SAMPLE_RATE;
#endif

	i2s_reader = i2s_stream_init(&i2s_cfg);

	// Create raw stream writer (to buffer)
	raw_stream_cfg_t raw_cfg = RAW_STREAM_CFG_DEFAULT();
	raw_cfg.type = AUDIO_STREAM_WRITER;
	raw_writer = raw_stream_init(&raw_cfg);

	// Register elements to pipeline
	audio_pipeline_register(pipeline, i2s_reader, "i2s");
	audio_pipeline_register(pipeline, raw_writer, "raw");

	// Link elements
	const char *link_tag[2] = { "i2s", "raw" };
	audio_pipeline_link(pipeline, &link_tag[0], 2);

	ESP_LOGI(TAG, "Audio pipeline initialized");
}

esp_err_t start_voice_recording(void)
{
	ESP_LOGI(TAG, "Starting voice recording for %d ms", RECORD_DURATION_MS);

	// Allocate buffer if not already done
	if (audio_buffer == NULL) {
		audio_buffer = malloc(AUDIO_BUFFER_SIZE);
		if (audio_buffer == NULL) {
			ESP_LOGE(TAG, "Failed to allocate audio buffer");
			return ESP_FAIL;
		}
	}

	audio_buffer_len = 0;

	// Reset pipeline
	audio_pipeline_reset_ringbuffer(pipeline);
	audio_pipeline_reset_elements(pipeline);

	// Start recording
	audio_pipeline_run(pipeline);

	// Read data from raw stream into buffer
	int bytes_read = 0;
	int timeout_counter = 0;

	while (audio_buffer_len < AUDIO_BUFFER_SIZE && timeout_counter < 100) {
		bytes_read = raw_stream_read(raw_writer, (char *)(audio_buffer + audio_buffer_len),
					     AUDIO_BUFFER_SIZE - audio_buffer_len);

		if (bytes_read > 0) {
			audio_buffer_len += bytes_read;
			timeout_counter = 0;
		} else {
			vTaskDelay(pdMS_TO_TICKS(10));
			timeout_counter++;
		}
	}

	// Stop recording
	audio_pipeline_stop(pipeline);
	audio_pipeline_wait_for_stop(pipeline);
	audio_pipeline_terminate(pipeline);

	ESP_LOGI(TAG, "Recording complete, captured %zu bytes", audio_buffer_len);

	return ESP_OK;
}
