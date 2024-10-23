import canvasity;
import gamut;
import quickview;

void main()
{
	ubyte[] data;
	data.length = 600*600*3;

	// Create an image from the data, using gamut's Image type
	Image image;
	image.createViewFromData(data.ptr, 600, 600, PixelType.rgb8, 600*3);

	// Use Canvasity to draw on the image
	with(Canvasity(image)) {
		// Background
		fillStyle("white");
		fillRect(0, 0, 600, 600);

		// Shadow
		shadowBlur    = 20;
		shadowOffsetX = 10;
		shadowOffsetY = 10;
		shadowColor("rgba(0, 0, 0, 0.8)");

		// Draw a purple rectangle
		fillStyle("purple");
		fillRect(60, 60, 480, 480);

		// Draw a circle
		fillStyle("yellow");
		fillRect(100, 100, 200, 200);
	}

	// Create a QuickView window and display the image
	QuickView w = new QuickView(600, 600, title: "Canvasity");
	w.buffer(data).draw();
	w.waitForClose();
}
