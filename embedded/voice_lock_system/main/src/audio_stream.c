/* Audio Streaming Implementation */

#include "audio_stream.h"
#include "config.h"
#include "esp_log.h"
#include "esp_http_client.h"
#include "audio_element.h"
#include "audio_pipeline.h"
#include "audio_common.h"
#include "http_stream.h"
#include "i2s_stream.h"
#include "board.h"
#include "audio_hal.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include <string.h>

static const char *TAG = "AUDIO_STREAM";

#define AUDIO_SAMPLE_RATE 44100
#define AUDIO_BITS 16
#define AUDIO_CHANNELS 1

static QueueHandle_t audio_stream_queue;
static audio_pipeline_handle_t pipeline;
static audio_element_handle_t i2s_stream_reader;
static audio_element_handle_t http_stream_writer;
static bool is_streaming = false;

esp_err_t _http_stream_event_handle(http_stream_event_msg_t *msg)
{
	esp_http_client_handle_t http = (esp_http_client_handle_t)msg->http_client;
	char len_buf[16];
	static int total_write = 0;

	if (msg->event_id == HTTP_STREAM_PRE_REQUEST) {
		ESP_LOGI(TAG, "HTTP client HTTP_STREAM_PRE_REQUEST");
		esp_http_client_set_method(http, HTTP_METHOD_POST);
		char dat[10] = { 0 };
		snprintf(dat, sizeof(dat), "%d", AUDIO_SAMPLE_RATE);
		esp_http_client_set_header(http, "x-audio-sample-rate", dat);
		memset(dat, 0, sizeof(dat));
		snprintf(dat, sizeof(dat), "%d", AUDIO_BITS);
		esp_http_client_set_header(http, "x-audio-bit-depth", dat);
		memset(dat, 0, sizeof(dat));
		snprintf(dat, sizeof(dat), "%d", AUDIO_CHANNELS);
		esp_http_client_set_header(http, "x-audio-channels", dat);
		esp_http_client_set_header(http, "Content-Type", "audio/raw");
		total_write = 0;
		return ESP_OK;
	}

	if (msg->event_id == HTTP_STREAM_ON_REQUEST) {
		int wlen = sprintf(len_buf, "%x\r\n", msg->buffer_len);
		if (esp_http_client_write(http, len_buf, wlen) <= 0) {
			return ESP_FAIL;
		}
		if (esp_http_client_write(http, msg->buffer, msg->buffer_len) <= 0) {
			return ESP_FAIL;
		}
		if (esp_http_client_write(http, "\r\n", 2) <= 0) {
			return ESP_FAIL;
		}
		total_write += msg->buffer_len;
		ESP_LOGD(TAG, "Total bytes written: %d", total_write);
		return msg->buffer_len;
	}

	if (msg->event_id == HTTP_STREAM_POST_REQUEST) {
		ESP_LOGI(TAG, "HTTP client HTTP_STREAM_POST_REQUEST, write end chunked marker");
		if (esp_http_client_write(http, "0\r\n\r\n", 5) <= 0) {
			return ESP_FAIL;
		}
		return ESP_OK;
	}

	if (msg->event_id == HTTP_STREAM_FINISH_REQUEST) {
		ESP_LOGI(TAG, "HTTP client HTTP_STREAM_FINISH_REQUEST");
		char *buf = calloc(1, 64);
		if (buf) {
			int read_len = esp_http_client_read(http, buf, 64);
			if (read_len > 0) {
				ESP_LOGI(TAG, "Got HTTP Response = %s", buf);
			}
			free(buf);
		}
		return ESP_OK;
	}
	return ESP_OK;
}

static void setup_pipeline(void)
{
	ESP_LOGI(TAG, "Setting up audio pipeline for streaming");

	// Initialize audio board
	audio_board_handle_t board_handle = audio_board_init();
	audio_hal_ctrl_codec(board_handle->audio_hal, AUDIO_HAL_CODEC_MODE_ENCODE, AUDIO_HAL_CTRL_START);

	audio_pipeline_cfg_t pipeline_cfg = DEFAULT_AUDIO_PIPELINE_CONFIG();
	pipeline = audio_pipeline_init(&pipeline_cfg);

	http_stream_cfg_t http_cfg = HTTP_STREAM_CFG_DEFAULT();
	http_cfg.type = AUDIO_STREAM_WRITER;
	http_cfg.event_handle = _http_stream_event_handle;
	http_stream_writer = http_stream_init(&http_cfg);

	i2s_stream_cfg_t i2s_cfg =
		I2S_STREAM_CFG_DEFAULT_WITH_TYLE_AND_CH(CODEC_ADC_I2S_PORT, 44100, 16, AUDIO_STREAM_READER, 1);
	i2s_cfg.type = AUDIO_STREAM_READER;
	i2s_cfg.out_rb_size = 64 * 1024; // Large buffer to prevent underruns
	i2s_stream_reader = i2s_stream_init(&i2s_cfg);

	audio_pipeline_register(pipeline, i2s_stream_reader, "i2s");
	audio_pipeline_register(pipeline, http_stream_writer, "http");

	const char *link_tag[2] = { "i2s", "http" };
	audio_pipeline_link(pipeline, &link_tag[0], 2);
}

static void teardown_pipeline(void)
{
	if (pipeline) {
		audio_pipeline_stop(pipeline);
		audio_pipeline_wait_for_stop(pipeline);
		audio_pipeline_terminate(pipeline);
		audio_pipeline_unregister(pipeline, http_stream_writer);
		audio_pipeline_unregister(pipeline, i2s_stream_reader);
		audio_pipeline_deinit(pipeline);
		audio_element_deinit(http_stream_writer);
		audio_element_deinit(i2s_stream_reader);
		pipeline = NULL;
	}
}

static void start_streaming(void)
{
	if (is_streaming) {
		ESP_LOGW(TAG, "Already streaming");
		return;
	}

	ESP_LOGI(TAG, "Starting audio streaming to %s", backend_url);
	ESP_LOGI(TAG, "Audio params: rate=%d, bits=%d, channels=%d", AUDIO_SAMPLE_RATE, AUDIO_BITS, AUDIO_CHANNELS);

	setup_pipeline();

	audio_element_set_uri(http_stream_writer, backend_url);

	audio_pipeline_run(pipeline);

	is_streaming = true;
	ESP_LOGI(TAG, "Audio streaming started");
}

static void stop_streaming(void)
{
	if (!is_streaming) {
		ESP_LOGW(TAG, "Not streaming");
		return;
	}

	ESP_LOGI(TAG, "Stopping audio streaming");

	audio_element_set_ringbuf_done(i2s_stream_reader);

	teardown_pipeline();

	is_streaming = false;
	ESP_LOGI(TAG, "Audio streaming stopped");
}

void audio_stream_task(void *pvParameters)
{
	audio_stream_cmd_t cmd;

	while (1) {
		if (xQueueReceive(audio_stream_queue, &cmd, portMAX_DELAY) == pdTRUE) {
			switch (cmd) {
			case AUDIO_STREAM_START:
				start_streaming();
				break;
			case AUDIO_STREAM_STOP:
				stop_streaming();
				break;
			default:
				ESP_LOGW(TAG, "Unknown command: %d", cmd);
				break;
			}
		}
	}
}

void audio_stream_init(void)
{
	audio_stream_queue = xQueueCreate(10, sizeof(audio_stream_cmd_t));
	xTaskCreate(audio_stream_task, "audio_stream", 4096, NULL, 5, NULL);
}

void audio_stream_send_cmd(audio_stream_cmd_t cmd)
{
	xQueueSend(audio_stream_queue, &cmd, 0);
}
