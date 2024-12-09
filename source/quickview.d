module quickview;

import std;
import core.thread : Thread, ThreadGroup;
import core.sync.event : Event;
import std.math : pow, sqrt;

public import bindbc.sdl;

// Some color conversion functions
Color rgb(ubyte r, ubyte g, ubyte b, ubyte a = 255) { return Color(r, g, b, a); }
Color rgb(string hex) { return Color.fromHex(hex); }
Color hsv(float h, float s, float v) { return Color.fromHSV(h, s, v); }
Color yuv(float y, float u, float v) { return Color.fromYUV(y, u, v); }
Color lab(float l, float a, float b) { return Color.fromCIELab(l, a, b); }

Color yuv(ubyte y, ubyte u, ubyte v) {
    float fy = y/255.0;
    float fu = (u/255.0) - 0.5;
    float fv = (v/255.0) - 0.5;
    return Color.fromYUV(fy, fu, fv);
}

class QuickView
{
    alias EventCallback = bool delegate(SDL_Event);

    public void onEvent(EventCallback callback) {
        eventCallback = callback;
    }

    shared static this() {
        SDLSupport ret = loadSDL();
        if(ret != sdlSupport) {
            // Handle errors
            throw new Exception("Failed to load SDL.");
        }

        if (SDL_Init(SDL_INIT_VIDEO) != 0)
            throw new Exception("Failed to initialize SDL: " ~ SDL_GetError().to!string);

    }

    shared static ~this() { SDL_Quit(); }


    private void addWindow(QuickView window, SDL_Window* sdlWindow) {
        synchronized { windows[sdlWindow] = window; }
    }

    private void removeWindow(SDL_Window* id) nothrow{

        synchronized {
            windows.remove(id);

            synchronized {
                if (windows.length == 0)
                {
                    running = false;
                    eventThread = null;
                }
            }
        }
    }


    this(ulong w, ulong h, string title = "QuickView", long x = -1, long y = -1, bool exitOnEscape = true) {

        this.width = w;
        this.height = h;

        uint flags = SDL_WINDOW_SHOWN | SDL_WINDOW_ALLOW_HIGHDPI;
        uint sx = SDL_WINDOWPOS_CENTERED, sy = SDL_WINDOWPOS_CENTERED;

        if (x >= 0) sx = cast(uint)x;
        if (y >= 0) sy = cast(uint)y;

        window = SDL_CreateWindow(title.toStringz, cast(int)sx, cast(int)sy, cast(int)width, cast(int)height, flags);
        id = window;
        addWindow(this, window);

        if (!window)
            throw new Exception("Failed to create SDL window: " ~ SDL_GetError().to!string);

        renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE | SDL_RENDERER_PRESENTVSYNC);

        if (!renderer)
            throw new Exception("Failed to create SDL renderer: " ~ SDL_GetError().to!string);

        texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGB24, SDL_TEXTUREACCESS_STREAMING, cast(int)width, cast(int)height);
        if (!texture)
            throw new Exception("Failed to create SDL texture: " ~ SDL_GetError().to!string);

        closeEvent = Event(true, false);

        _buffer.length = width * height * 3;
    }

    ~this() { free(); }

    private void free() nothrow {
        if (window is null) return;
        if (texture) {
            SDL_DestroyTexture(texture);
            texture = null;
        }
        if (renderer) {
            SDL_DestroyRenderer(renderer);
            renderer = null;
        }
        SDL_DestroyWindow(window);
        window = null;
        removeWindow(id);
        closeEvent.setIfInitialized();
    }


    QuickView clear(Color color = Color(255, 255, 255)) {

        auto r = color.r, g = color.g, b = color.b;

        foreach(i; 0.._buffer.length/3) {
            _buffer[i*3+0] = r;
            _buffer[i*3+1] = g;
            _buffer[i*3+2] = b;
        }

        buffer(_buffer);

        return this;
    }

    void close() nothrow {
        SDL_Event event;
        event.type = SDL_QUIT;
        SDL_PushEvent(&event);
        free();
    }

    bool isClosed() nothrow { return window is null; }
    bool isOpen() nothrow { return !isClosed(); }

    QuickView buffer(T)(T[] buf, bool wait = false) {
        if (!window)
            return this;

        synchronized {
            auto minLen = min(_buffer.length, buf.length);

            static if (is(T == ubyte) || is (T == byte)) _buffer[0..minLen] = cast(ubyte[])(buf[0..minLen]).dup;
            else static if (isIntegral!T) _buffer[0..minLen] = buf.map!(x => cast(ubyte)x).array[0..minLen].dup;
            else static if (is(T == float)) _buffer[0..minLen] = buf.map!(x => cast(ubyte)(x * 255)).array[0..minLen].dup;
            else static assert(false, "Invalid buffer type");
        }

        if (wait)
        {
            draw();
            waitForClose();
        }

        return this;
    }

    QuickView draw() nothrow {
        if (window is null) return this;

        synchronized {
            SDL_UpdateTexture(texture, null, _buffer.ptr, cast(int)width * 3);
            SDL_RenderClear(renderer);
            SDL_RenderCopy(renderer, texture, null, null);
            SDL_RenderPresent(renderer);
        }

        return this;
    }

    static void waitForAll() {
        foreach (w; windows)
            w.waitForClose();
    }

    void waitForClose() {
        runEventLoop(this);
    }


    private void processEvent(SDL_Event event)  {
        static long lastFocus = 0;

        bool handled = false;

        if (eventCallback)
            handled = eventCallback(event);

        if (event.type == SDL_WINDOWEVENT)
        {
            switch (event.window.event) {
                case SDL_WINDOWEVENT_SHOWN:
                case SDL_WINDOWEVENT_FOCUS_GAINED:
                    lastFocus = event.common.timestamp;
                    break;

                case SDL_WINDOWEVENT_EXPOSED:
                    draw();
                    break;
                default: break;
            }
        }

        if (!handled)
        {
            switch (event.type) {
                case SDL_WINDOWEVENT:
                    if (event.window.event == SDL_WINDOWEVENT_CLOSE)
                        free();
                    break;

                case SDL_QUIT:
                    free();
                    break;

                case SDL_KEYDOWN:
                    if (event.key.keysym.sym == SDLK_ESCAPE && event.common.timestamp - lastFocus > 10)
                        free();
                    break;
                default:
                    break;
            }
        }
    }

    private static void runEventLoop(QuickView window = null) {
        running = true;

        while (running && (window is null || window.isOpen())) {
            runEventLoopIterationImpl(true);
        }
    }

    static void runEventLoopIteration() {
        runEventLoopIterationImpl(false);
    }

    private static void runEventLoopIterationImpl(bool wait = false) {
        SDL_Event event;

        again:
        auto ret = wait?SDL_WaitEvent(&event):SDL_PollEvent(&event);

        if (ret) {

            if ([SDL_WINDOWEVENT, SDL_MOUSEBUTTONDOWN, SDL_MOUSEBUTTONUP, SDL_MOUSEMOTION, SDL_KEYDOWN, SDL_KEYUP].canFind(event.type)) {

                auto wid = SDL_GetWindowFromID(event.window.windowID);
                auto w = wid in windows;

                if (w)
                {
                    synchronized {
                        w.processEvent(event);
                    }
                }
            }

            else if (event.type == SDL_QUIT) {
                foreach (w; windows)
                    w.free();
            }
        }

        if (ret && !wait)
            goto again;
    }

    static void terminate() {
        SDL_Event quitEvent;
        quitEvent.type = SDL_QUIT;
        SDL_PushEvent(&quitEvent);

        running = false;
        if (eventThread !is null) {
            eventThread.join();
        }
    }


    QuickView rect(T)(T boundingBox, Color color, bool fill = true, long stroke = 1) {
        BoundingBox bb;
        bb.parse(boundingBox);
        rectImpl(bb.x, bb.y, bb.w, bb.h, color, fill, stroke);
        return this;
    }


    QuickView rect(long x = long.max, long y = long.max, long x1 = long.max, long y1 = long.max, long w = long.max, long h = long.max, long cx = long.max, long cy = long.max, Color color, bool fill = true, long stroke = 1) {
        BoundingBox bb;
        bb.x = x;
        bb.y = y;
        bb.x1 = x1;
        bb.y1 = y1;
        bb.w = w;
        bb.h = h;
        bb.cx = cx;
        bb.cy = cy;

        bb.solve();

        rectImpl(bb.x, bb.y, bb.w, bb.h, color, fill, stroke);
        return this;
    }

    pragma(inline, true)
    private void setPixel(long x, long y, ubyte r, ubyte g, ubyte b, ubyte a) {
        if (x >= 0 && x < width && y >= 0 && y < height) {
                long index = (y * width + x) * 3;
                _buffer[index] = cast(ubyte)((r * a + _buffer[index] * (255 - a)) / 255);
                _buffer[index + 1] = cast(ubyte)((g * a + _buffer[index + 1] * (255 - a)) / 255);
                _buffer[index + 2] = cast(ubyte)((b * a + _buffer[index + 2] * (255 - a)) / 255);
        }
    }

    private QuickView rectImpl(long x, long y, long w, long h, Color color, bool fill = true, long stroke = 1) {
        auto r = color.r, g = color.g, b = color.b, a = color.a;

        synchronized {
            if (fill) {
                // Fill the rectangle
                for (long dy = 0; dy < h; dy++) {
                    for (long dx = 0; dx < w; dx++) {
                        setPixel(x + dx, y + dy, r, g, b, a);
                    }
                }
            }

            // Draw borders with stroke
            for (long s = 0; s < stroke; s++) {
                // Top and bottom borders
                for (long dx = 0; dx < w; dx++) {
                    setPixel(x + dx, y + s, r, g, b, a);                  // Top
                    setPixel(x + dx, y + h - 1 - s, r, g, b, a);         // Bottom
                }
                // Left and right borders
                for (long dy = 0; dy < h; dy++) {
                    setPixel(x + s, y + dy, r, g, b, a);                 // Left
                    setPixel(x + w - 1 - s, y + dy, r, g, b, a);        // Right
                }
            }
        }

        return this;
    }

    QuickView line(long x1, long y1, long x2, long y2, Color color, long thickness = 1) {
        auto r = color.r, g = color.g, b = color.b, a = color.a;

        return lineImpl(x1, y1, x2, y2, r, g, b, a, thickness);
    }

    private QuickView lineImpl(long x1, long y1, long x2, long y2, ubyte r, ubyte g, ubyte b, ubyte a, long thickness = 1) {
        // Bresenham's line algorithm without clipping
        long dx = abs(x2 - x1);
        long dy = abs(y2 - y1);
        long sx = x1 < x2 ? 1 : -1;
        long sy = y1 < y2 ? 1 : -1;
        long err = dx - dy;

        while (true) {
            synchronized {
                for (long tx = -thickness / 2; tx <= thickness / 2; tx++) {
                    for (long ty = -thickness / 2; ty <= thickness / 2; ty++) {
                        setPixel(x1 + tx, y1 + ty, r, g, b, a);
                    }
                }
            }

            if (x1 == x2 && y1 == y2) break;

            long e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                x1 += sx;
            }
            if (e2 < dx) {
                err += dx;
                y1 += sy;
            }
        }

        return this;
    }

    QuickView path(long[][] polongs, Color color, long thickness = 1, bool close = false) {
        if (polongs.length < 2) {
            throw new Exception("Path must have at least 2 polongs");
        }

        try {
            auto r = color.r, g = color.g, b = color.b, a = color.a;

            for (long i = 0; i < polongs.length - 1; i++) {
                lineImpl(polongs[i][0], polongs[i][1], polongs[i+1][0], polongs[i+1][1], r, g, b, a, thickness);
            }

            if (close && polongs.length > 2) {
                lineImpl(polongs[$-1][0], polongs[$-1][1], polongs[0][0], polongs[0][1], r, g, b, a, thickness);
            }

        }
        catch (Exception e) {
            throw new Exception("Error drawing path: " ~ e.msg);
        }

        return this;
    }

    QuickView circle(T)(T boundingBox, Color color, bool fill = true, long stroke = 1) {
        BoundingBox bb;
        bb.parse(boundingBox);
        circleImpl(bb.x, bb.y, bb.w, color, fill, stroke);
        return this;
    }

    QuickView circle(long x = long.max, long y = long.max, long x1 = long.max, long y1 = long.max, long diameter = long.max, long cx = long.max, long cy = long.max, Color color, bool fill = true, long stroke = 1) {
        BoundingBox bb;
        bb.x = x;
        bb.y = y;
        bb.x1 = x1;
        bb.y1 = y1;
        bb.w = diameter;
        bb.h = diameter;
        bb.cx = cx;
        bb.cy = cy;

        bb.solve();

        circleImpl(bb.x, bb.y, bb.w, color, fill, stroke);

        return this;
    }

    private QuickView circleImpl(long x, long y, long diameter, Color color, bool fill = true, long stroke = 1) {
        ovalImpl(x, y, diameter, diameter, color, fill, stroke);
        return this;
    }

    QuickView oval(T)(T boundingBox, Color color, bool fill = true, long stroke = 1) {
        BoundingBox bb;
        bb.parse(boundingBox);
        ovalImpl(bb.x, bb.y, bb.w, bb.h, color, fill, stroke);
        return this;
    }

    QuickView oval(long x = long.max, long y = long.max, long x1 = long.max, long y1 = long.max, long w = long.max, long h = long.max, long cx = long.max, long cy = long.max, Color color, bool fill = true, long stroke = 1) {
        BoundingBox bb;
        bb.x = x;
        bb.y = y;
        bb.x1 = x1;
        bb.y1 = y1;
        bb.w = w;
        bb.h = h;
        bb.cx = cx;
        bb.cy = cy;

        bb.solve();

        ovalImpl(bb.x, bb.y, bb.w, bb.h, color, fill, stroke);
        return this;
    }

    private QuickView ovalImpl(long x, long y, long w, long h, Color color, bool fill = true, long stroke = 1) {
        try {
            auto r = color.r, g = color.g, b = color.b, a = color.a;

            long centerX = x + w / 2;
            long centerY = y + h / 2;
            long radiusX = w / 2;
            long radiusY = h / 2;

            // Per il riempimento, usiamo un approccio scanline per evitare sovrapposizioni
            if (fill) {
                for (long dy = -radiusY; dy <= radiusY; dy++) {
                    long py = centerY + dy;
                    // Calcola i punti di intersezione per questa scanline
                    float dx = radiusX * sqrt(1.0 - (dy * dy) / cast(float)(radiusY * radiusY));
                    long startX = cast(long)(centerX - dx);
                    long endX = cast(long)(centerX + dx);

                    // Disegna la linea orizzontale una sola volta
                    for (long px = startX; px <= endX; px++) {
                        setPixel(px, py, r, g, b, a);
                    }
                }
            }

            // Per il bordo, usiamo l'algoritmo originale ma solo per il contorno
            if (stroke > 0) {
                long rx2 = radiusX * radiusX;
                long ry2 = radiusY * radiusY;
                long twoRx2 = 2 * rx2;
                long twoRy2 = 2 * ry2;
                long p;
                long px = 0;
                long py = twoRx2 * radiusY;
                long xx = 0;
                long yy = radiusY;

                void drawOvalPoints(long cx, long cy, long x, long y) {
                    for (long st = 0; st < stroke; st++) {
                        setPixel(cx + x + st, cy + y, r, g, b, a);
                        setPixel(cx - x - st, cy + y, r, g, b, a);
                        setPixel(cx + x + st, cy - y, r, g, b, a);
                        setPixel(cx - x - st, cy - y, r, g, b, a);
                    }
                }

                // Region 1
                p = cast(long)round(ry2 - (rx2 * radiusY) + (0.25 * rx2));
                while (px < py) {
                    drawOvalPoints(centerX, centerY, cast(long)xx, cast(long)yy);
                    xx++;
                    px += twoRy2;
                    if (p < 0)
                        p += ry2 + px;
                    else {
                        yy--;
                        py -= twoRx2;
                        p += ry2 + px - py;
                    }
                }

                // Region 2
                p = cast(long)round(ry2 * (xx + 0.5) * (xx + 0.5) + rx2 * (yy - 1) * (yy - 1) - rx2 * ry2);
                while (yy > 0) {
                    drawOvalPoints(centerX, centerY, cast(long)xx, cast(long)yy);
                    yy--;
                    py -= twoRx2;
                    if (p > 0)
                        p += rx2 - py;
                    else {
                        xx++;
                        px += twoRy2;
                        p += rx2 - py + px;
                    }
                }

                drawOvalPoints(centerX, centerY, cast(long)xx, 0);
            }
        }
        catch (Exception e) {
            throw new Exception("Error drawing oval: " ~ e.msg);
        }

        return this;
    }

    void saveAs(string filename) {

        if (!filename.toLower().endsWith(".png"))
            throw new Exception("Invalid file extension");

        void writeChunk(ref ubyte[] pngData, string type, const(ubyte)[] data) const {
            import std.bitmanip : nativeToBigEndian;
            import std.digest.crc : crc32Of;
            import std.array : array;
            import std.range : retro;

            // Write chunk length
            pngData ~= nativeToBigEndian(cast(uint)data.length);

            // Calculate CRC of type and data
            ubyte[] crcData = cast(ubyte[])type ~ data;
            auto crc = crc32Of(crcData);

            // Write type, data, and CRC
            pngData ~= type;
            pngData ~= data;
            pngData ~= crc[].retro.array;
        }

        import std.bitmanip : nativeToBigEndian;

        ubyte[] pngData;

        // PNG signature
        pngData ~= [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

        // IHDR chunk
        ubyte[] ihdr;
        ihdr.reserve(13);

        ihdr ~= nativeToBigEndian(cast(uint)width);      // Width
        ihdr ~= nativeToBigEndian(cast(uint)height);     // Height
        ihdr ~= [8, 2, 0, 0, 0];  // Bit depth (8), Color type (2 - RGB), Compression, Filter, Interlace
        writeChunk(pngData, "IHDR", ihdr);

        // Image data
        ubyte[] idat;
        idat.reserve((width * 3 + 1) * height);  // 3 bytes per pixel + 1 filter byte per row

        // Write the image data
        foreach (y; 0 .. height) {
            idat ~= 0;  // Filter type for each scanline
            foreach (x; 0 .. width) {
                size_t bufferIndex = (y * width + x) * 3;
                idat ~= _buffer[bufferIndex .. bufferIndex + 3];
            }
        }

        import std.zlib : compress;
        writeChunk(pngData, "IDAT", compress(idat, 9));

        // IEND chunk
        writeChunk(pngData, "IEND", []);

        // Write to file
        import std.file : write;
        write(filename, pngData);
    }

    private:

        ubyte[]         _buffer;
        ulong            width, height;
        bool            closed = false;
        SDL_Window*     window = null;
        SDL_Renderer*   renderer;
        SDL_Texture*    texture;
        SDL_Window*     id;
        Event           closeEvent;
        EventCallback   eventCallback = null;

        __gshared Thread        eventThread;
        __gshared bool          running = true;
        __gshared Thread        mainThread;

        __gshared QuickView[SDL_Window*] windows;
}



struct Color {
    ubyte r, g, b, a;

    @disable this();

    Color alpha(ubyte a) {
        return Color(r, g, b, a);
    }

    this(ubyte r, ubyte g, ubyte b, ubyte a = 255) {
        this.r = r;
        this.g = g;
        this.b = b;
        this.a = a;
    }


    static Color fromYUV(float y, float u, float v) {

        debug {
            if (y < 0.0f || y > 1.0f || u < -0.5f || u > 0.5f || v < -0.5f || v > 0.5f)
                stderr.writeln("Invalid YUV values: ", y, " ", u, " ", v);
        }

        // Ensure Y, U, and V are in the correct range
        y = clamp(y, 0.0f, 1.0f);
        u = clamp(u, -0.5f, 0.5f);
        v = clamp(v, -0.5f, 0.5f);

        // Convert YUV to RGB
        float r = y + 1.13983f * v;
        float g = y - 0.39465f * u - 0.58060f * v;
        float b = y + 2.03211f * u;

        // Clamp RGB values to [0, 1] range
        r = clamp(r, 0.0f, 1.0f);
        g = clamp(g, 0.0f, 1.0f);
        b = clamp(b, 0.0f, 1.0f);

        // Convert float values to ubyte (0-255 range)
        ubyte rByte = cast(ubyte)(r * 255);
        ubyte gByte = cast(ubyte)(g * 255);
        ubyte bByte = cast(ubyte)(b * 255);

        return Color(rByte, gByte, bByte);
    }

    static Color fromHex(string color) {

        ubyte r, g, b, a;
        if (color.length == 7) {
            r = color[1..3].to!ubyte(16);
            g = color[3..5].to!ubyte(16);
            b = color[5..7].to!ubyte(16);
            a = 255;
        }
        else if (color.length == 9) {
            r = color[1..3].to!ubyte(16);
            g = color[3..5].to!ubyte(16);
            b = color[5..7].to!ubyte(16);
            a = color[7..9].to!ubyte(16);
        }
        else throw new Exception("Invalid color format");

        return Color(r, g, b, a);
    }


    static Color fromHSV(float h, float s, float v) {

        debug {
            if (h < 0.0f || h > 360.0f || s < 0.0f || s > 1.0f || v < 0.0f || v > 1.0f)
                stderr.writeln("Invalid HSV values: ", h, " ", s, " ", v);
        }

        h = clamp(h, 0.0f, 360.0f);
        s = clamp(s, 0.0f, 1.0f);
        v = clamp(v, 0.0f, 1.0f);

        float c = v * s;
        float x = c * (1 - abs((h / 60) % 2 - 1));
        float m = v - c;

        float r, g, b;
        if (h < 60) { r = c; g = x; b = 0; }
        else if (h < 120) { r = x; g = c; b = 0; }
        else if (h < 180) { r = 0; g = c; b = x; }
        else if (h < 240) { r = 0; g = x; b = c; }
        else if (h < 300) { r = x; g = 0; b = c; }
        else { r = c; g = 0; b = x; }

        ubyte rByte = cast(ubyte)((r + m) * 255);
        ubyte gByte = cast(ubyte)((g + m) * 255);
        ubyte bByte = cast(ubyte)((b + m) * 255);

        return Color(rByte, gByte, bByte);
    }

    static Color fromCIELab(float l, float a, float b) {
        debug {
            if (l < 0.0f || l > 1.0f || a < -0.5f || a > 0.5f || b < -0.5f || b > 0.5f)
                stderr.writeln("Invalid Lab values: ", l, " ", a, " ", b);
        }

        // Clamp values to normalized ranges
        l = clamp(l, 0.0f, 1.0f);
        a = clamp(a, -0.5f, 0.5f);
        b = clamp(b, -0.5f, 0.5f);

        // Scale to traditional Lab ranges
        float l_scaled = l * 100.0f;                // 0..1   -> 0..100
        float a_scaled = a * 256.0f;                // -0.5..0.5 -> -128..128
        float b_scaled = b * 256.0f;                // -0.5..0.5 -> -128..128

        // First convert to XYZ
        float y = (l_scaled + 16.0f) / 116.0f;
        float x = a_scaled / 500.0f + y;
        float z = y - b_scaled / 200.0f;

        // Helper function for the conversion
        float f(float t) {
            return t > 0.206893f ? t * t * t : (t - 16.0f / 116.0f) / 7.787f;
        }

        x = 0.95047f * f(x);
        y = 1.00000f * f(y);
        z = 1.08883f * f(z);

        // Then convert XYZ to RGB
        float r = x *  3.2406f + y * -1.5372f + z * -0.4986f;
        float g = x * -0.9689f + y *  1.8758f + z *  0.0415f;
        float b_ = x *  0.0557f + y * -0.2040f + z *  1.0570f;

        // Convert to sRGB and clamp
        r = clamp(r, 0.0f, 1.0f);
        g = clamp(g, 0.0f, 1.0f);
        b_ = clamp(b_, 0.0f, 1.0f);

        // Convert to 8-bit values
        ubyte rByte = cast(ubyte)(r * 255);
        ubyte gByte = cast(ubyte)(g * 255);
        ubyte bByte = cast(ubyte)(b_ * 255);

        return Color(rByte, gByte, bByte);
    }
}


private struct BoundingBox {

    long x = long.max, y = long.max, w = long.max, h = long.max, cx = long.max, cy = long.max, x1 = long.max, y1 = long.max;

    void parse(T)(T bb){
        // Check if bb has x,y,w,h
        static if (__traits(compiles, x = cast(long)bb.x, y = cast(long)bb.y, w = cast(long)bb.w, h = cast(long)bb.h)) {
            x = cast(long)bb.x;
            y = cast(long)bb.y;
            w = cast(long)bb.w;
            h = cast(long)bb.h;
        }
        else static if (__traits(compiles, x = cast(long)bb.x0, y = cast(long)bb.y0, w = cast(long)bb.x1 - cast(long)bb.x0, h = cast(long)bb.y1 - cast(long)bb.y0)) {
            x = cast(long)bb.x0;
            y = cast(long)bb.y0;
            w = cast(long)bb.x1 - cast(long)bb.x0;
            h = cast(long)bb.y1 - cast(long)bb.y0;
        }
        else static if (__traits(compiles, x = cast(long)bb.x1, y = cast(long)bb.y1, w = cast(long)bb.x2 - cast(long)bb.x1, h = cast(long)bb.y2 - cast(long)bb.y1)) {
            x = cast(long)bb.x1;
            y = cast(long)bb.y1;
            w = cast(long)bb.x2 - cast(long)bb.x1;
            h = cast(long)bb.y2 - cast(long)bb.y1;
        }
        else static if (__traits(compiles, x = cast(long)bb.cx - cast(long)bb.w/2, y = cast(long)bb.cy - cast(long)bb.h/2, w = cast(long)bb.w, h = cast(long)bb.h)) {
            x = cast(long)bb.cx - cast(long)bb.w/2;
            y = cast(long)bb.cy - cast(long)bb.h/2;
            w = cast(long)bb.w;
            h = cast(long)bb.h;
        }
        else static if(__traits(compiles, x = cast(long)bb.tl[0], y = cast(long)bb.tl[1], w = cast(long)bb.br[0]-cast(long)bb.tl[0], h = cast(long)bb.br[1]-cast(long)bb.tl[1])) {
            x = cast(long)bb.tl[0];
            y = cast(long)bb.tl[1];
            w = cast(long)bb.br[0]-cast(long)bb.tl[0];
            h = cast(long)bb.br[1]-cast(long)bb.tl[1];
        }
        else static assert(false, "Invalid bounding box");
    }

    void solve() nothrow {

        if (x != long.max && y != long.max && x1 != long.max && y1 != long.max) {
            w = x1 - x;
            h = y1 - y;
        }

        if (cx != long.max && cy != long.max && w != long.max && h != long.max) {
           x = cx - w/2;
           y = cy - h/2;
        }

        cx = x + w/2;
        cy = y + h/2;

        x1 = x + w;
        y1 = y + h;
    }

}


version(OSX) {
    extern(C) {
        void* dispatch_get_main_queue();
        void dispatch_async(void* queue, void function() block);
    }
}