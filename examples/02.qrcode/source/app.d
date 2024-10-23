import std.stdio;
import qr;
import quickview;

void main()
{
	// Some "random" links
	auto qr1 = QrCode("https://github.com/trikko/serverino");
	auto qr2 = QrCode("https://github.com/trikko/qr");

	// Render the QR codes, each in a separate window and pop them up
	QuickView w1 = render(qr1, "QR #1");
	QuickView w2 = render(qr2, "QR #2");

	w1.waitForClose(); // Wait for the first window to close
	writeln("First window closed");

	w2.waitForClose(); // Wait for the second window to close
	writeln("Second window closed");
}

QuickView render(QrCode qr, string title)
{
	// The size of the QR code + 2 modules, in pixels
	size_t size = (qr.size + 4) * 10;

	// Create a window with the size of the QR code + 2 modules on each side
	auto w = new QuickView(w: size, h: size, title: title);

	// Clear the screen with white
	w.clear(rgb("#ffffff"));

	// Draw the QR code
	foreach(y; 0..qr.size)
		foreach(x; 0..qr.size)
			if (qr[x,y])
				w.rect(x: 20 + x*10, y:20 + y*10, w:10, h:10, color:rgb("#000000"));

	w.draw();
	return w;
}