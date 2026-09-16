/* Minimal pw_stream video consumer: counts frames for N seconds.
 * Usage: pwcount [seconds] [width height] */
#include <stdio.h>
#include <stdlib.h>
#include <pipewire/pipewire.h>
#include <spa/param/video/format-utils.h>

struct data {
	struct pw_main_loop *loop;
	struct pw_stream *stream;
	int frames;
	int frames_at_switch;
	int switched;
};

static void on_process(void *userdata)
{
	struct data *d = userdata;
	struct pw_buffer *b = pw_stream_dequeue_buffer(d->stream);

	if (b == NULL)
		return;
	d->frames++;
	pw_stream_queue_buffer(d->stream, b);
}

static void on_timeout(void *userdata, uint64_t expirations)
{
	struct data *d = userdata;

	pw_main_loop_quit(d->loop);
}

/* Renegotiate to another size mid-stream, like OBS changing its resolution */
static void on_switch(void *userdata, uint64_t expirations)
{
	struct data *d = userdata;
	uint8_t buffer[1024];
	struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
	const struct spa_pod *params[1];
	struct spa_rectangle size = d->switched++ % 2 ? SPA_RECTANGLE(1920, 1080) :
						       SPA_RECTANGLE(640, 480);

	params[0] = spa_pod_builder_add_object(&b,
			SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
			SPA_FORMAT_mediaType, SPA_POD_Id(SPA_MEDIA_TYPE_video),
			SPA_FORMAT_mediaSubtype, SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
			SPA_FORMAT_VIDEO_size, SPA_POD_Rectangle(&size));
	d->frames_at_switch = d->frames;
	fprintf(stderr, "switch to %ux%u after %d frames\n", size.width, size.height, d->frames);
	pw_stream_update_params(d->stream, params, 1);
}

static const struct pw_stream_events stream_events = {
	PW_VERSION_STREAM_EVENTS,
	.process = on_process,
};

int main(int argc, char *argv[])
{
	struct data d = { 0 };
	const struct spa_pod *params[1];
	uint8_t buffer[1024];
	struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
	int seconds = argc > 1 ? atoi(argv[1]) : 3;
	int width = argc > 3 ? atoi(argv[2]) : 0, height = argc > 3 ? atoi(argv[3]) : 0;
	struct timespec value = { seconds, 0 }, interval = { 0, 0 };

	pw_init(&argc, &argv);
	d.loop = pw_main_loop_new(NULL);
	d.stream = pw_stream_new_simple(pw_main_loop_get_loop(d.loop), "pwcount",
			pw_properties_new(PW_KEY_MEDIA_TYPE, "Video",
					  PW_KEY_MEDIA_CATEGORY, "Capture",
					  PW_KEY_MEDIA_ROLE, "Camera", NULL),
			&stream_events, &d);

	if (width > 0)
		params[0] = spa_pod_builder_add_object(&b,
				SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
				SPA_FORMAT_mediaType, SPA_POD_Id(SPA_MEDIA_TYPE_video),
				SPA_FORMAT_mediaSubtype, SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
				SPA_FORMAT_VIDEO_size, SPA_POD_Rectangle(&SPA_RECTANGLE(width, height)));
	else
		params[0] = spa_pod_builder_add_object(&b,
				SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
				SPA_FORMAT_mediaType, SPA_POD_Id(SPA_MEDIA_TYPE_video),
				SPA_FORMAT_mediaSubtype, SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw));

	pw_stream_connect(d.stream, PW_DIRECTION_INPUT, PW_ID_ANY,
			PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS,
			params, 1);

	struct spa_source *timer = pw_loop_add_timer(pw_main_loop_get_loop(d.loop),
			on_timeout, &d);
	pw_loop_update_timer(pw_main_loop_get_loop(d.loop), timer, &value, &interval, false);

	/* PWCOUNT_SWITCH=N: renegotiate the size every N seconds */
	if (getenv("PWCOUNT_SWITCH")) {
		struct timespec every = { atoi(getenv("PWCOUNT_SWITCH")), 0 };
		struct spa_source *sw = pw_loop_add_timer(pw_main_loop_get_loop(d.loop),
				on_switch, &d);
		pw_loop_update_timer(pw_main_loop_get_loop(d.loop), sw, &every, &every, false);
	}

	pw_main_loop_run(d.loop);
	if (d.switched)
		printf("%d (after last switch: %d)\n", d.frames, d.frames - d.frames_at_switch);
	else
		printf("%d\n", d.frames);

	pw_stream_destroy(d.stream);
	pw_main_loop_destroy(d.loop);
	pw_deinit();
	return 0;
}
