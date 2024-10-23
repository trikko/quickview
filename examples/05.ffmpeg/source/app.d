import std;
import quickview;

// This example shows how to use ffmpeg to read an image and display it in a QuickView window
// It's a quick and dirty way to display images in a window without loading a D image library even in rare formats

void main()
{
	// Showing a sunraster image (public domain)
	showImage("mushroom.im1", "Image from disk");

	// Showing a jpg image, from internet
	showImage("https://upload.wikimedia.org/wikipedia/commons/thumb/c/cf/Sidney_Hall_-_Urania%27s_Mirror_-_Scorpio.jpg/536px-Sidney_Hall_-_Urania%27s_Mirror_-_Scorpio.jpg", "Remote image");

	// Showing the first frame from a video, from internet
	showImage("https://www.pexels.com/download/video/1851190/?fps=25.0&h=540&w=960", "Frame from remote video");

	QuickView.waitForAll();
}

void showImage(string src, string title = "")
{
	// Open a pipe to the ffmpeg command, converting data to raw rgb24 format
	auto cmd = pipeProcess(
		[
			"ffmpeg", "-i", src,	// Input file
			"-vf", "showinfo",	// Video filter to get info
			"-vframes", "1",		// Always extract one frame
			"-f", "rawvideo",
			"-pix_fmt", "rgb24",
			"-"
		], Redirect.all
	);

	// Buffer for reading data from the pipe
	ubyte[] buffer;
	buffer.length = 1024*16;

	// Read pixels from stdout
	ubyte[] pixels;
	while(cmd.stdout.isOpen)
	{
		auto rd = cmd.stdout.rawRead(buffer);
		if (rd.length == 0) break;
		pixels ~= rd;
	}

	// Read image info from stderr
	ubyte[] info;
	while(cmd.stderr.isOpen)
	{
		auto rd = cmd.stderr.rawRead(buffer);
		if (rd.length == 0) break;
		info ~= rd;
	}

	// Trying to get the resolution from the info
	auto line = (cast(char[])info)
		.split('\n')
		.filter!(x => x.canFind("_showinfo_"))
		.filter!(x => x.canFind(" s:"));

	if (line.empty)
	{
		writeln(src, ": could not find image resolution in the info output");
		return;
	}

	auto data = line.front.matchFirst(ctRegex!(r"s:(\d+)x(\d+)"));

	if (!data)
	{
		writeln(src, ": could not parse image resolution from the info output");
		return;
	}

	// Create a QuickView window with the resolution of the video
	QuickView w = new QuickView(data[1].to!int, data[2].to!int, title);
	w.buffer(pixels);
	w.draw();
}
