import std;
import quickview;

// You need to install libvlc to run this example

__gshared QuickView display;
__gshared ubyte[] buffer;
__gshared libvlc_media_player_t* player;

enum VIDEO_WIDTH = 1296/2; 	// It's fixed on the example video resolution
enum VIDEO_HEIGHT = 1080/2;	// It's fixed on the example video resolution


extern(C)
void* begin_vlc_rendering(void* data, void** p_pixels)
{
	// We pass the buffer to VLC. VLC will fill it with the video frame
	if (buffer.length > 0) *p_pixels = buffer.ptr;
	else *p_pixels = null;
	return null;
}

extern(C)
void render_frame(void* opaque, void* picture)
{
	// Get the current position of the video
	float pos = min(1, max(0, libvlc_media_player_get_position(player)));

	if (buffer.length > 0)
	{
		// Copy the buffer to the display
	 	display.buffer(buffer[0..VIDEO_WIDTH*VIDEO_HEIGHT*3]);


		// Draw the seek bar and the border
		display.rect(x: 10, y: VIDEO_HEIGHT - 40, w: cast(int)((VIDEO_WIDTH - 20)*pos), h: 30, color: rgb("#345522cc"), fill: true);
		display.rect(x: 10, y: VIDEO_HEIGHT - 40, w: VIDEO_WIDTH - 20, h: 30, color: rgb("#345522ff"), stroke: 5, fill: false);

		// Render the display
		display.draw();
	}

	// If the video is at the end, restart it
	if (pos >= 1)
	{
		libvlc_media_player_pause(player);
		libvlc_media_player_set_position(player, 0.0f);
		libvlc_media_player_play(player);
	}
}

void main() {

	writeln("--------------------------------");
	writeln("libvlc example - streaming video");
	writeln("--------------------------------");
	writeln("Press space to restart the video");
	writeln("Press left/right to seek");
	writeln("--------------------------------");

	display = new QuickView(VIDEO_WIDTH, VIDEO_HEIGHT, title: "QuickView + VLC");
	buffer.length = VIDEO_WIDTH*VIDEO_HEIGHT*3;

	// Create a VLC instance
	libvlc_instance_t* libvlc = libvlc_new(4, ["--verbose=-1", "--no-xlib", "--drop-late-frames", "--live-caching=0"].map!(x => x.toStringz).array.ptr);

	if (libvlc == null)
		throw new Exception("Failed to create VLC instance. Did you install libvlc?");

	// Create a media from the video file (also: file:///path/to/video.mp4)
	libvlc_media_t* media = libvlc_media_new_location(libvlc, ("https://upload.wikimedia.org/wikipedia/commons/5/5f/Steamboat_Willie_%281928%29_by_Walt_Disney.webm").toStringz);

	// Create a player from the media
	player = libvlc_media_player_new_from_media(media);
	libvlc_media_release(media);

	// Set callback for frame drawing
	libvlc_video_set_callbacks(player, &begin_vlc_rendering, null, &render_frame, null);

	// Pause the player and set the video format
	libvlc_media_player_pause(player);
	libvlc_video_set_format(player, "RV24", VIDEO_WIDTH, VIDEO_HEIGHT, VIDEO_WIDTH*3);

	// Start playing the video
	libvlc_media_player_play(player);

	display.onEvent = (event) {
		// Keyboard events
		if (event.type == SDL_KEYDOWN)
		{
			// Ignore repeated keys
			if (event.key.repeat) return true;

			// Space to restart the video
			if (event.key.keysym.sym == SDLK_SPACE)
			{
				libvlc_media_player_stop(player);
				libvlc_media_player_set_position(player, 0.0f);
				libvlc_media_player_play(player);
				return true;
			}
			// Left to seek backward
			else if (event.key.keysym.sym == SDLK_LEFT)
			{
				libvlc_media_player_set_position(player, libvlc_media_player_get_position(player) - 0.03f);
				libvlc_media_player_play(player);
				return true;
			}
			// Right to seek forward
			else if (event.key.keysym.sym == SDLK_RIGHT)
			{
				libvlc_media_player_set_position(player, libvlc_media_player_get_position(player) + 0.03f);
				libvlc_media_player_play(player);
				return true;
			}
		}
		// Mouse events
		else if (event.type == SDL_MOUSEBUTTONDOWN)
		{
			// Check if the mouse is over the seek bar
			if (event.button.x >= 10 && event.button.x <= VIDEO_WIDTH - 10 && event.button.y >= VIDEO_HEIGHT - 40 && event.button.y <= VIDEO_HEIGHT - 10)
			{
				libvlc_media_player_set_position(player, (event.button.x - 10)/cast(float)(VIDEO_WIDTH - 20));
				libvlc_media_player_play(player);
				return true;
			}
		}
		return false;
	};

	// Wait for the window to close
	display.waitForClose();

	writeln("Goodbye!");

}

// VLC C API
extern (C) {
	struct libvlc_instance_t;
	struct libvlc_media_t;
	struct libvlc_media_player_t;

	libvlc_instance_t* libvlc_new(long argc, const(char*)* argv);

	libvlc_media_t* libvlc_media_new_location(libvlc_instance_t* p_instance, const(char)* psz_mrl);

	libvlc_media_player_t* libvlc_media_player_new_from_media(libvlc_media_t* p_media);

	void libvlc_media_release(libvlc_media_t* p_media);

	void libvlc_video_set_callbacks(
		libvlc_media_player_t* mp,
		void* function(void* opaque, void** planes) lock,
		void function(void* opaque, void* picture, void** planes) unlock,
		void function(void* opaque, void* picture) display,
		void* opaque
	);

	long libvlc_media_player_play(libvlc_media_player_t* p_mi);
	long libvlc_media_player_stop(libvlc_media_player_t* p_mi);
	void libvlc_media_player_release(libvlc_media_player_t* p_mi);
	void libvlc_release(libvlc_instance_t* p_instance);

	long libvlc_media_player_pause(libvlc_media_player_t* p_mi);

	float libvlc_media_player_get_position(libvlc_media_player_t* p_mi);
	void libvlc_media_player_set_position(libvlc_media_player_t* p_mi, float f_pos);

	void libvlc_video_set_format(
		libvlc_media_player_t* mp,
		const(char)* chroma,
		ulong width,
		ulong height,
		ulong pitch
	);

	long libvlc_video_get_size(
		libvlc_media_player_t* p_mi,
		ulong num,
		ulong* px,
		ulong* py
	);

	void libvlc_media_add_option(libvlc_media_t* p_media, const(char)* psz_options);
}
