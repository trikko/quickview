module app;

import std;
import quickview;

// This example shows a quick way to display a video in a QuickView window using ffmpeg
void main()
{
	// Showing a sunraster image (public domain)
	showVideo("https://upload.wikimedia.org/wikipedia/commons/5/5f/Steamboat_Willie_%281928%29_by_Walt_Disney.webm");
	QuickView.waitForAll();
}

void showVideo(string src, string title = "")
{
	auto cmdLine = ["ffmpeg", "-re", "-i", src];

	version(linux) cmdLine ~= ["-f", "pulse", "default"];
	version(osx) cmdLine ~= ["-f", "coreaudio"];
	version(windows) cmdLine ~= ["-f", "dshow"];

	cmdLine ~= ["-f", "rawvideo", "-pix_fmt", "rgb24", "-"];

	// Open a pipe to the ffmpeg command, converting data to raw rgb24 format
	auto cmd = pipeProcess(cmdLine, Redirect.all);

	// Fixed resolution of the video (for the example video)
	int width = 1296;
	int height = 1080;

	// Buffer for reading data from the pipe
	ubyte[] buffer;
	buffer.length = width*height*3;

	// Create a QuickView window with the resolution of the video
	QuickView w = new QuickView(width, height, "Video with ffmpeg");

	while(cmd.stdout.isOpen && w.isOpen)
	{
		// Read pixels from stdout
		ubyte[] pixels;
		pixels.reserve(width*height*3);

		while(cmd.stdout.isOpen && pixels.length < width*height*3)
		{
			pixels.length = 0;
			auto rd = cmd.stdout.rawRead(buffer);
			if (rd.length == 0) break;
			pixels ~= rd;
		}

		w.buffer(pixels[0..width*height*3]);
		w.draw();

		pixels = pixels[width*height*3..$];

		QuickView.runEventLoopIteration();
	}
}
