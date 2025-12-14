/* Audio Streaming Implementation */

#include "audio_common.h"
#include "audio_element.h"
#include "audio_hal.h"
#include "audio_pipeline.h"
#include "audio_stream.h"
#include "board.h"
#include "config.h"
#include "driver/gpio.h"
#include "esp_crt_bundle.h"
#include "esp_heap_caps.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_timer.h"
#include <sys/time.h>
#include <time.h>
#include "filter_resample.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "i2s_stream.h"
#include "lock.h"
#include "math.h"
#include "mqtt.h"
#include "raw_stream.h"
#include "sdkconfig.h"
#include <string.h>

extern TaskHandle_t idle_blink_task;
extern audio_board_handle_t g_board_handle;

static const char *TAG = "\033[1mLOCKWISE:\033[92mAUDIO\033[0m\033[92m";

#define AUDIO_SAMPLE_RATE 16000
#define AUDIO_BITS 16
#define AUDIO_CHANNELS 1
#define NOISE_RMS_THRESHOLD 1000.0
#define VAD_FRAME_MS 30
#define VAD_SAMPLES ((AUDIO_SAMPLE_RATE * VAD_FRAME_MS) / 1000)
#define VAD_TRIGGER_FRAMES 6
#define VAD_COOLDOWN_MS 2000
#define MIN_SECONDS 5.0
#define BYTES_PER_SEC (AUDIO_SAMPLE_RATE * AUDIO_CHANNELS * (AUDIO_BITS / 8))
#define MIN_BYTES ((size_t)(MIN_SECONDS * BYTES_PER_SEC))

static QueueHandle_t audio_stream_queue;
static audio_pipeline_handle_t pipeline;
static audio_element_handle_t i2s;
static audio_element_handle_t raw;
static volatile bool streaming_enabled = false;
static volatile bool recording_active = false;
static SemaphoreHandle_t stream_gate;
static size_t pcm_bytes_sent = 0;
static int64_t last_stream_us = 0;

static void audio_init_pipeline(void)
{
	ESP_LOGI(TAG, "Initializing single audio pipeline");

	audio_hal_ctrl_codec(g_board_handle->audio_hal, AUDIO_HAL_CODEC_MODE_ENCODE, AUDIO_HAL_CTRL_START);

	audio_pipeline_cfg_t pipeline_cfg = DEFAULT_AUDIO_PIPELINE_CONFIG();
	pipeline = audio_pipeline_init(&pipeline_cfg);

	i2s_stream_cfg_t i2s_cfg = I2S_STREAM_CFG_DEFAULT_WITH_TYLE_AND_CH(
		CODEC_ADC_I2S_PORT, AUDIO_SAMPLE_RATE, AUDIO_BITS, AUDIO_STREAM_READER, AUDIO_CHANNELS);
	i2s_cfg.out_rb_size = 128 * 1024;
	i2s = i2s_stream_init(&i2s_cfg);

	raw_stream_cfg_t raw_cfg = {
		.out_rb_size = 256 * 1024,
		.type = AUDIO_STREAM_READER,
	};
	raw = raw_stream_init(&raw_cfg);

	audio_pipeline_register(pipeline, i2s, "i2s");
	audio_pipeline_register(pipeline, raw, "raw");

	const char *links[] = { "i2s", "raw" };
	audio_pipeline_link(pipeline, links, 2);

	audio_pipeline_run(pipeline);
}

static void vad_task(void *arg)
{
	ESP_LOGI(TAG, "Starting VAD task");

	const size_t frame_bytes = VAD_SAMPLES * sizeof(int16_t);
	int16_t *frame_buf = heap_caps_malloc(frame_bytes, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
	if (!frame_buf) {
		ESP_LOGE(TAG, "Failed to allocate VAD buffer");
		vTaskDelete(NULL);
	}

	uint8_t *tmp = heap_caps_malloc(4096, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
	if (!tmp) {
		ESP_LOGE(TAG, "Failed to allocate tmp buffer");
		free(frame_buf);
		vTaskDelete(NULL);
	}

	vTaskDelay(pdMS_TO_TICKS(5000)); // codec settle

	int speech_frames = 0;
	int64_t last_trigger_us = 0;

	while (1) {
		if (streaming_enabled) {
			speech_frames = 0;
			vTaskDelay(pdMS_TO_TICKS(50));
			continue;
		}

		size_t have = 0;
		int64_t t0 = esp_timer_get_time();

		// Accumulate until we have a full frame or timeout after ~200ms
		while (have < frame_bytes && (esp_timer_get_time() - t0) < 200000) {
			int r = raw_stream_read(raw, (char *)tmp,
						(4096 < (frame_bytes - have)) ? 4096 : (frame_bytes - have));
			if (r > 0) {
				memcpy(((uint8_t *)frame_buf) + have, tmp, r);
				have += r;
			} else if (r == 0) {
				// no data currently; give up CPU briefly to avoid busy loop
				vTaskDelay(pdMS_TO_TICKS(5));
			} else {
				// negative -> error; break and try again later
				ESP_LOGW(TAG, "raw_stream_read error: %d", r);
				break;
			}
		}

		if (have < frame_bytes) {
			// not enough data this round, try again later
			// optional: print small debug every few seconds
			vTaskDelay(pdMS_TO_TICKS(10));
			continue;
		}

		// compute RMS on frame_buf (int16 samples)
		double rms = 0.0;
		for (int i = 0; i < VAD_SAMPLES; i++) {
			double s = (double)frame_buf[i];
			rms += s * s;
		}
		rms = sqrt(rms / VAD_SAMPLES);

		// debug logging occasionally
		static int dbg_cnt = 0;
		if ((dbg_cnt++ & 31) == 0)
			ESP_LOGD(TAG, "VAD frame RMS=%.2f", rms);

		if (rms > NOISE_RMS_THRESHOLD)
			speech_frames++;
		else
			speech_frames = 0;

		if (speech_frames >= VAD_TRIGGER_FRAMES) {
			int64_t now = esp_timer_get_time();
			if (now - last_trigger_us > VAD_COOLDOWN_MS * 1000) {
				last_trigger_us = now;
				ESP_LOGI(TAG, "VAD triggered (RMS %.2f)", rms);
				streaming_enabled = true;
				xSemaphoreGive(stream_gate);
			}
			speech_frames = 0;
		}
	}

	// unreachable
	free(frame_buf);
	free(tmp);
	vTaskDelete(NULL);
}

static void http_stream_task(void *arg)
{
	ESP_LOGI(TAG, "Starting HTTP stream task");

	while (1) {
		xSemaphoreTake(stream_gate, portMAX_DELAY);

		// Reset pipeline to discard stale audio
		audio_pipeline_stop(pipeline);
		audio_pipeline_wait_for_stop(pipeline);
		audio_pipeline_terminate(pipeline);
		audio_pipeline_reset_ringbuffer(pipeline);
		audio_pipeline_reset_elements(pipeline);
		audio_pipeline_run(pipeline);
		vTaskDelay(pdMS_TO_TICKS(200)); // Wait for codec to settle

		char voice_url[512];
		snprintf(voice_url, sizeof(voice_url), "%s/verify_voice/%s", config.backend_url, config.device_id);

		// Debug: print wall clock time and CA bundle status
		struct timeval tv;
		gettimeofday(&tv, NULL);
		time_t now = tv.tv_sec;
		struct tm tm;
		localtime_r(&now, &tm);
		ESP_LOGI(TAG, "Wall clock: %04d-%02d-%02d %02d:%02d:%02d (epoch=%lld)", tm.tm_year + 1900,
			 tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec, (long long)now);
		ESP_LOGI(TAG, "CA bundle attach ptr: %p", esp_crt_bundle_attach);

		esp_http_client_config_t http_cfg = {
			.url = voice_url,
			.method = HTTP_METHOD_POST,
			.crt_bundle_attach = (strncmp(config.backend_url, "https://", 8) == 0) ? esp_crt_bundle_attach :
												 NULL,
			.timeout_ms = 15000,
			.buffer_size_tx = 4096,
			.buffer_size = 4096,
		};
		esp_http_client_handle_t http = esp_http_client_init(&http_cfg);
		if (!http) {
			ESP_LOGE(TAG, "Failed to init HTTP client");
			streaming_enabled = false;
			continue;
		}

		// Set headers
		char dat[10];
		snprintf(dat, sizeof(dat), "%d", AUDIO_SAMPLE_RATE);
		esp_http_client_set_header(http, "x-audio-sample-rate", dat);
		snprintf(dat, sizeof(dat), "%d", AUDIO_BITS);
		esp_http_client_set_header(http, "x-audio-bit-depth", dat);
		snprintf(dat, sizeof(dat), "%d", AUDIO_CHANNELS);
		esp_http_client_set_header(http, "x-audio-channels", dat);
		esp_http_client_set_header(http, "Content-Type", "application/octet-stream");
		if (strlen(config.backend_bearer_token) > 0) {
			char auth_header[256 + 10];
			snprintf(auth_header, sizeof(auth_header), "Bearer %s", config.backend_bearer_token);
			esp_http_client_set_header(http, "Authorization", auth_header);
		}

		// Buffer audio until MIN_BYTES
		uint8_t *audio_buffer = heap_caps_malloc(MIN_BYTES, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
		if (!audio_buffer) {
			ESP_LOGE(TAG, "Failed to allocate audio buffer");
			esp_http_client_cleanup(http);
			streaming_enabled = false;
			continue;
		}

		pcm_bytes_sent = 0;
		recording_active = true;

		mqtt_publish_status("STREAMING");
		gpio_set_level(LOCK_INDICATOR_LED_GPIO, 1);
		if (idle_blink_task)
			vTaskSuspend(idle_blink_task);

		uint8_t *buf = heap_caps_malloc(4096, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
		if (!buf) {
			ESP_LOGE(TAG, "Failed to allocate HTTP buffer");
			free(audio_buffer);
			recording_active = false;
			continue;
		}

		// Buffer audio
		while (recording_active && pcm_bytes_sent < MIN_BYTES) {
			int n = raw_stream_read(raw, (char *)buf, 4096);
			if (n > 0) {
				if (pcm_bytes_sent + n > MIN_BYTES) {
					n = MIN_BYTES - pcm_bytes_sent;
				}
				memcpy(audio_buffer + pcm_bytes_sent, buf, n);
				pcm_bytes_sent += n;
			}
		}

		free(buf);

		if (pcm_bytes_sent >= MIN_BYTES) {
			// Send with Content-Length
			char length_str[16];
			snprintf(length_str, sizeof(length_str), "%zu", pcm_bytes_sent);
			esp_http_client_set_header(http, "Content-Length", length_str);

			esp_err_t err = esp_http_client_open(http, pcm_bytes_sent);
			if (err != ESP_OK) {
				ESP_LOGE(TAG, "Failed to open HTTP connection: %s", esp_err_to_name(err));
				free(audio_buffer);
				esp_http_client_cleanup(http);
				streaming_enabled = false;
				continue;
			}

			int written = esp_http_client_write(http, (char *)audio_buffer, pcm_bytes_sent);
			if (written != pcm_bytes_sent) {
				ESP_LOGE(TAG, "HTTP write failed: %d != %zu", written, pcm_bytes_sent);
			}
		} else {
			ESP_LOGW(TAG, "Not enough audio buffered: %zu < %zu", pcm_bytes_sent, MIN_BYTES);
		}

		free(audio_buffer);

		// Fetch headers before checking status
		esp_http_client_fetch_headers(http);

		int status_code = esp_http_client_get_status_code(http);
		ESP_LOGI(TAG, "HTTP Status Code = %d", status_code);
		if (status_code == 200) {
			toggle_door(DOOR_REASON_VOICE);
		}

		// Drain the response body fully
		char response_buf[128];
		int total_read = 0;
		int read_len;
		do {
			read_len = esp_http_client_read(http, response_buf, sizeof(response_buf) - 1);
			if (read_len > 0) {
				response_buf[read_len] = 0;
				ESP_LOGI(TAG, "HTTP response chunk: %s", response_buf);
				total_read += read_len;
			}
		} while (read_len > 0);
		ESP_LOGI(TAG, "Total response bytes read: %d", total_read);
		esp_http_client_close(http);
		esp_http_client_cleanup(http);

		recording_active = false;
		streaming_enabled = false;

		mqtt_publish_status("STOPPED_STREAMING");
		gpio_set_level(LOCK_INDICATOR_LED_GPIO, 0);
		if (idle_blink_task)
			vTaskResume(idle_blink_task);

		ESP_LOGI(TAG, "Sent %zu bytes", pcm_bytes_sent);
		if (pcm_bytes_sent < MIN_BYTES) {
			ESP_LOGW(TAG, "Sent less than minimum bytes: %zu < %zu", pcm_bytes_sent, MIN_BYTES);
		}
	}
}

void audio_stream_task(void *pvParameters)
{
	audio_stream_cmd_t cmd;

	for (;;) {
		if (xQueueReceive(audio_stream_queue, &cmd, portMAX_DELAY) == pdTRUE) {
			switch (cmd) {
			case AUDIO_STREAM_START:
				if (!streaming_enabled) {
					streaming_enabled = true;
					xSemaphoreGive(stream_gate);
				}
				break;
			case AUDIO_STREAM_STOP:
				recording_active = false;
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
	esp_log_level_set(TAG, ESP_LOG_INFO);
	audio_stream_queue = xQueueCreate(10, sizeof(audio_stream_cmd_t));
	stream_gate = xSemaphoreCreateBinary();
	audio_init_pipeline();
	xTaskCreate(audio_stream_task, "audio_stream", 4096, NULL, 5, NULL);
	xTaskCreate(vad_task, "vad", 8192, NULL, 4, NULL);
	xTaskCreate(http_stream_task, "http_stream", 8192, NULL, 5, NULL);
}

void audio_stream_send_cmd(audio_stream_cmd_t cmd)
{
	xQueueSend(audio_stream_queue, &cmd, 0);
}
