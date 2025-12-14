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
#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "filter_resample.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "http_stream.h"
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

#define AUDIO_SAMPLE_RATE 44100
#define AUDIO_BITS 16
#define AUDIO_CHANNELS 1
#define NOISE_RMS_THRESHOLD 2000.0

static QueueHandle_t audio_stream_queue;
static audio_pipeline_handle_t pipeline;
static audio_element_handle_t i2s_stream_reader;
static audio_element_handle_t http_stream_writer;
static bool is_streaming = false;
static esp_timer_handle_t stop_timer = NULL;

// Monitoring for noise detection
static audio_pipeline_handle_t pipeline_mon;
static audio_element_handle_t i2s_mon;
static audio_element_handle_t raw_mon;
static TaskHandle_t monitoring_task_handle;
static bool speech_detected = false;
static SemaphoreHandle_t vad_mutex;

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
		esp_http_client_set_header(http, "Content-Type", "application/octet-stream");
		if (strlen(config.backend_bearer_token) > 0) {
			char auth_header[256 + 10];
			snprintf(auth_header, sizeof(auth_header), "Bearer %s", config.backend_bearer_token);
			esp_http_client_set_header(http, "Authorization", auth_header);
		}
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
		int status_code = esp_http_client_get_status_code(http);
		ESP_LOGI(TAG, "HTTP Status Code = %d", status_code);
		if (status_code == 200)
			toggle_door(DOOR_REASON_VOICE);
		char *buf = calloc(1, 64);
		if (buf) {
			int read_len = esp_http_client_read(http, buf, 64);
			if (read_len > 0)
				ESP_LOGI(TAG, "Got HTTP Response = %s", buf);
			free(buf);
		}
		return ESP_OK;
	}
	return ESP_OK;
}

static void stop_timer_callback(void *arg)
{
	audio_stream_send_cmd(AUDIO_STREAM_STOP);
}

static void setup_monitoring_pipeline(void)
{
	ESP_LOGI(TAG, "Setting up monitoring pipeline for noise detection");

	audio_hal_ctrl_codec(g_board_handle->audio_hal, AUDIO_HAL_CODEC_MODE_ENCODE, AUDIO_HAL_CTRL_START);

	audio_pipeline_cfg_t pipeline_cfg = DEFAULT_AUDIO_PIPELINE_CONFIG();
	pipeline_mon = audio_pipeline_init(&pipeline_cfg);

	i2s_stream_cfg_t i2s_cfg = I2S_STREAM_CFG_DEFAULT_WITH_TYLE_AND_CH(CODEC_ADC_I2S_PORT, 44100, 16, AUDIO_STREAM_READER, 1);
	i2s_mon = i2s_stream_init(&i2s_cfg);

	raw_stream_cfg_t raw_cfg = {
		.out_rb_size = 8 * 1024,
		.type = AUDIO_STREAM_READER,
	};
	raw_mon = raw_stream_init(&raw_cfg);

	audio_pipeline_register(pipeline_mon, i2s_mon, "i2s_mon");
	audio_pipeline_register(pipeline_mon, raw_mon, "raw_mon");

	const char *link_tag[2] = { "i2s_mon", "raw_mon" };
	audio_pipeline_link(pipeline_mon, &link_tag[0], 2);

	audio_pipeline_run(pipeline_mon);
}

static void teardown_monitoring_pipeline(void)
{
	if (pipeline_mon) {
		audio_pipeline_stop(pipeline_mon);
		audio_pipeline_wait_for_stop(pipeline_mon);
		audio_pipeline_terminate(pipeline_mon);
		audio_pipeline_unregister(pipeline_mon, i2s_mon);
		audio_pipeline_unregister(pipeline_mon, raw_mon);
		audio_pipeline_deinit(pipeline_mon);
		audio_element_deinit(i2s_mon);
		audio_element_deinit(raw_mon);
		pipeline_mon = NULL;
	}
}



static void monitoring_task(void *pvParameters)
{
	ESP_LOGI(TAG, "Starting noise monitoring task");

	int16_t *vad_buff = (int16_t *)malloc(480 * sizeof(short)); // 30ms at 16kHz
	if (!vad_buff) {
		ESP_LOGE(TAG, "Failed to allocate VAD buffer");
		vTaskDelete(NULL);
		return;
	}

	// Wait 5 seconds after setup to ignore initialization noise
	vTaskDelay(pdMS_TO_TICKS(5000));

	while (1) {
		if (!pipeline_mon) {
			setup_monitoring_pipeline();
		}

		int ret = raw_stream_read(raw_mon, (char *)vad_buff, 480 * sizeof(short));
		if (ret > 0) {
			long long sum = 0;
			for (int i = 0; i < 480; i++) {
				sum += (long long)vad_buff[i] * vad_buff[i];
			}
			double rms = sqrt(sum / 480.0);
			xSemaphoreTake(vad_mutex, portMAX_DELAY);
			if (!speech_detected && rms > NOISE_RMS_THRESHOLD) {
				speech_detected = true;
				ESP_LOGI(TAG, "Noise detected (RMS %.2f > %.2f), starting streaming", rms,
					 NOISE_RMS_THRESHOLD);
				audio_stream_send_cmd(AUDIO_STREAM_START);
			}
			xSemaphoreGive(vad_mutex);
		} else {
			ESP_LOGW(TAG, "Failed to read from raw stream");
			vTaskDelay(pdMS_TO_TICKS(100));
		}
	}

	free(vad_buff);
	vTaskDelete(NULL);
}

static void setup_pipeline(void)
{
	ESP_LOGI(TAG, "Setting up audio pipeline for streaming");

	// Initialize audio board
	audio_hal_ctrl_codec(g_board_handle->audio_hal, AUDIO_HAL_CODEC_MODE_ENCODE, AUDIO_HAL_CTRL_START);

	audio_pipeline_cfg_t pipeline_cfg = DEFAULT_AUDIO_PIPELINE_CONFIG();
	pipeline = audio_pipeline_init(&pipeline_cfg);

	http_stream_cfg_t http_cfg = HTTP_STREAM_CFG_DEFAULT();
	// Configure TLS for HTTPS URLs
	if (strncmp(config.backend_url, "https://", 8) == 0) {
		http_cfg.crt_bundle_attach = esp_crt_bundle_attach;
		ESP_LOGI(TAG, "HTTP TLS enabled with certificate bundle");
	}
	http_cfg.type = AUDIO_STREAM_WRITER;
	http_cfg.event_handle = _http_stream_event_handle;
	http_stream_writer = http_stream_init(&http_cfg);

	i2s_stream_cfg_t i2s_cfg = I2S_STREAM_CFG_DEFAULT_WITH_TYLE_AND_CH(CODEC_ADC_I2S_PORT, 44100, 16, AUDIO_STREAM_READER, 1);
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
		mqtt_publish_status("ERR_ALREADY_STREAMING");
		ESP_LOGW(TAG, "Already streaming");
		return;
	}
	is_streaming = true;

	mqtt_publish_status("STREAMING");
	ESP_LOGI(TAG, "Starting audio streaming to %s", config.backend_url);
	ESP_LOGI(TAG, "Audio params: rate=%d, bits=%d, channels=%d", AUDIO_SAMPLE_RATE, AUDIO_BITS, AUDIO_CHANNELS);

	setup_pipeline();

	char voice_url[512];
	snprintf(voice_url, sizeof(voice_url), "%s/verify_voice/%s", config.backend_url, config.device_id);
	audio_element_set_uri(http_stream_writer, voice_url);

	audio_pipeline_run(pipeline);

	gpio_set_level(LOCK_INDICATOR_LED_GPIO, 1);
	if (idle_blink_task)
		vTaskSuspend(idle_blink_task);
	// Stop monitoring while streaming
	teardown_monitoring_pipeline();
	if (monitoring_task_handle)
		vTaskSuspend(monitoring_task_handle);
	ESP_LOGI(TAG, "Audio streaming started");

	if (!stop_timer) {
		esp_timer_create_args_t timer_args = { .callback = &stop_timer_callback,
						       .arg = NULL,
						       .dispatch_method = ESP_TIMER_TASK,
						       .name = "stop_timer" };
		esp_timer_create(&timer_args, &stop_timer);
	}
	esp_timer_start_once(stop_timer,
			     config.audio_record_timeout_sec * 1000000); // config.audio_record_timeout_sec seconds
}

static void stop_streaming(void)
{
	if (!is_streaming) {
		mqtt_publish_status("ERR_NOT_STREAMING");
		ESP_LOGW(TAG, "Not streaming");
		return;
	}

	mqtt_publish_status("STOPPED_STREAMING");
	ESP_LOGI(TAG, "Stopping audio streaming");

	if (stop_timer) {
		esp_timer_stop(stop_timer);
		esp_timer_delete(stop_timer);
		stop_timer = NULL;
	}

	audio_element_set_ringbuf_done(i2s_stream_reader);

	teardown_pipeline();

	is_streaming = false;
	if (idle_blink_task)
		vTaskResume(idle_blink_task);
	gpio_set_level(LOCK_INDICATOR_LED_GPIO, 0);
	// Reset speech detection flag, resume monitoring task
	xSemaphoreTake(vad_mutex, portMAX_DELAY);
	speech_detected = false;
	xSemaphoreGive(vad_mutex);
	if (monitoring_task_handle)
		vTaskResume(monitoring_task_handle);
	ESP_LOGI(TAG, "Audio streaming stopped");
}

void audio_stream_task(void *pvParameters)
{
	audio_stream_cmd_t cmd;

	for (;;) {
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
	esp_log_level_set(TAG, ESP_LOG_INFO);
	audio_stream_queue = xQueueCreate(10, sizeof(audio_stream_cmd_t));
	vad_mutex = xSemaphoreCreateMutex();
	xTaskCreate(audio_stream_task, "audio_stream", 4096, NULL, 5, NULL);
	xTaskCreate(monitoring_task, "audio_monitor", 4096, NULL, 4, &monitoring_task_handle);
}

void audio_stream_send_cmd(audio_stream_cmd_t cmd)
{
	xQueueSend(audio_stream_queue, &cmd, 0);
}
