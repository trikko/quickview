import std;
import std.datetime.stopwatch;
import core.thread;

import opensimplexnoise;
import quickview;

void main()
{
	writeln("--------------------------------");
	writeln("OpenSimplex example - press Enter to save a screenshot");
	writeln("--------------------------------");

	QuickView display = new QuickView(512, 512, title: "OpenSimplex");

	// OpenSimplex noise generator
	auto noise = new OpenSimplexNoise!float();

	// Stopwatch to measure the frame time
	StopWatch watch;
	watch.start();

	// Press Enter to save the image
	display.onEvent = (event) {
		if (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_RETURN)
		{
			// Synchronized to ensure the image is saved correctly
			// since this event is called from another thread
			synchronized display.saveAs("screenshot-" ~ watch.peek.total!"msecs".to!string ~ ".png");
			return true;
		}
		return false;
	};

	while(display.isOpen)
	{
		// Get the current time
		auto t = watch.peek;

		// 32x32 grid. Keep the buffer synchronized to ensure the image is saved correctly
		synchronized {
			foreach(y; 0..32)
			{
				foreach(x; 0..32)
				{
					// 2D noise
					float h = 360*min(1, max(0, (0.7 + noise.eval(7+x/14.0f, 13+y/14.0f, 0.0028f*t.total!"msecs"))/1.4));
					float s = 0.8;
					float v = 0.3 + 0.7*min(1, max(0, (0.7 + noise.eval(x/20.0f, y/20.0f, 0.0028f*t.total!"msecs"))/1.4));

					// Draw a 16x16 rectangle at (x,y) with the calculated HSV color
					display.rect(
						x: x*16, y: y*16,
						w: 16, h: 16,
						color: hsv(h,s,v),
						fill: true
					);
				}
			}
		}

		// Draw the data to the screen
		display.draw();

		// Trying to keep ~30fps
		auto delta = (watch.peek - t).total!"msecs";
		Thread.sleep(max(0, 30 - cast(int)delta).msecs);

		display.runEventLoopIteration();
	}

}
