import std.stdio;
import quickview;

void main()
{
	// Create a checkerboard pattern
	ubyte[800*600*3] pixels;
	foreach(y; 0..600)
	{
		foreach(x; 0..800)
		{
			// 50x50 checkerboard pattern with two shades of gray
			ubyte color = cast(ubyte)(50 + (((x / 50 + y / 50) % 2) * 100));
			size_t index = (y * 800 + x) * 3;
			pixels[index..index+3] = color;
		}
	}

	new QuickView(800, 600) // Also new QuickView(w: 800, h: 600)
		.buffer(pixels)		// Set the buffer to the checkerboard pattern
		.circle(cx: 400, cy: 300, diameter: 200, color: rgb("#99dd33")) // Draw a circle
		.draw() 					// Draw the buffer to the screen
		.waitForClose();		// Wait for the window to be closed

	writeln("QuickView closed. Exiting.");
}
