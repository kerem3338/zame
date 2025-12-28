module zame.core.font;

import std.conv;
import std.string;
import std.utf;
import std.file;
import std.array;
import zame.core.common;
import zame.core.graphics;

class BitmapFont {
	struct Glyph {
		int x;
		int y;
		int w;
		int h;
		int advance;
	}

	string name;
	int size;
	int lineHeight;
	int widthSpacing = 1;

	Surface atlas;
	Glyph[dchar] glyphs;

	this(string atlasPath, string infoPath, int spacing = 1) {
		widthSpacing = spacing;
		loadAtlas(atlasPath);
		readInfo(infoPath);
	}

	void loadAtlas(string path) {
		atlas = new Surface(1, 1);
		auto res = loadFromPng(atlas, path);
		if (res.result != Result.ok)
			throw new Exception("Failed to load font atlas: " ~ path);
	}

	void readInfo(string path) {
		auto lines = readText(path).splitLines;
		size_t i = 0;

		while (i < lines.length && lines[i].strip != "---") {
			auto l = lines[i].strip;
			if (l.startsWith("name:str:"))
				name = l["name:str:".length .. $];
			else if (l.startsWith("size:int:"))
				size = l["size:int:".length .. $].to!int;
			else if (l.startsWith("lineHeight:int:"))
				lineHeight = l["lineHeight:int:".length .. $].to!int;
			i++;
		}

		if (i < lines.length && lines[i].strip == "---")
			i++;

		for (; i < lines.length; i++) {
			auto l = lines[i].strip;
			if (l.length == 0) continue;

			auto parts = l.split;
			if (parts.length < 2) continue;

			size_t idx = 0;
			dchar ch = decode(l, idx);

			Glyph g;
			foreach (p; parts[1 .. $]) {
				auto kv = p.split("=");
				if (kv.length != 2) continue;

				final switch(kv[0]) {
					case "x": g.x = kv[1].to!int; break;
					case "y": g.y = kv[1].to!int; break;
					case "w": g.w = kv[1].to!int; break;
					case "h": g.h = kv[1].to!int; break;
				}
			}

			glyphs[ch] = g;
		}

		if (!('?' in glyphs))
			throw new Exception("BitmapFont requires '?' fallback glyph");
	}

	private float safeScale(int fontSize) {
		int maxH = 1;
		foreach (g; glyphs.byValue)
			if (g.h > maxH) maxH = g.h;

		return cast(float)fontSize / maxH;
	}

	private Surface renderNative(string text, Color color) {
		int w = 0;
		foreach (dchar c; text)
			w += (c in glyphs ? glyphs[c].w : glyphs['?'].w);

		auto outSurf = new Surface(w, lineHeight);
		outSurf.fill(Color(0,0,0,0));

		int cx = 0;
		foreach (dchar c; text) {
			auto g = (c in glyphs) ? glyphs[c] : glyphs['?'];

			if (c == ' ') {
				cx += g.w;
				continue;
			}

			for (int y = 0; y < g.h; y++)
			for (int x = 0; x < g.w; x++) {
				auto src = atlas.rawData[(g.y+y)*atlas.width + (g.x+x)];
				// Assume white is transparent background, black/colors are text
				// Intensity (0-255) will be our alpha mask. 
				// 0 (black) -> full alpha, 255 (white) -> zero alpha
				int intensity = 255 - ((src.r + src.g + src.b) / 3);
				if (intensity <= 0) continue;

				uint finalAlpha = cast(uint)(color.a * intensity / 255);
				if (finalAlpha == 0) continue;

				outSurf.rawData[y*outSurf.width + (cx+x)] =
					Color(color.r, color.g, color.b, finalAlpha);
			}

			cx += g.w;
		}

		return outSurf;
	}

	Surface getText(string text, Color color, int fontSize) {
		auto native = renderNative(text, color);
		float scale = safeScale(fontSize);

		auto scaled = scaleSurface(
			native,
			cast(int)(native.width * scale),
			fontSize
		);

		return applySafeSpacing(scaled, text, scale);
	}

	private Surface applySafeSpacing(Surface src, string text, float scale) {
		int count = text.length.to!int;
		if (count <= 1) return src;

		int spacing = cast(int)(widthSpacing * scale);

		int avgGlyphW = src.width / count;
		int maxSpacing = avgGlyphW / 4;
		if (spacing > maxSpacing)
			spacing = maxSpacing;

		if (spacing <= 0)
			return src;

		int finalW = src.width + spacing * (count - 1);
		auto outSurf = new Surface(finalW, src.height);
		outSurf.fill(Color(0,0,0,0));

		int sx = 0;
		int dx = 0;

		foreach (i, dchar c; text) {
			auto g = (c in glyphs) ? glyphs[c] : glyphs['?'];
			int gw = cast(int)(g.w * scale);

			for (int y = 0; y < src.height; y++)
			for (int x = 0; x < gw; x++)
				outSurf.rawData[y*finalW + dx+x] =
					src.rawData[y*src.width + sx+x];

			sx += gw;
			dx += gw;
			if (i < count-1) dx += spacing;
		}

		return outSurf;
	}
}

class GenericBitmapFont {
	struct Glyph {
		int width;
		int height;
		bool[][] pixels;
	}

	string path;
	string name;
	int width;
	int height;

	Glyph[dchar] glyphs;

	this(string path) {
		this.path = path;
		readFont();
	}

	void readFont() {
		auto text = readText(path);
		auto lines = text.splitLines;
		size_t i = 0;

		while (i < lines.length && lines[i] != "---") {
			auto l = lines[i];
			if (l.startsWith("name:str:"))
				name = l["name:str:".length .. $];
			else if (l.startsWith("width:int:"))
				width = l["width:int:".length .. $].to!int;
			else if (l.startsWith("height:int:"))
				height = l["height:int:".length .. $].to!int;
			i++;
		}

		if (i < lines.length && lines[i] == "---")
			i++;

		while (i < lines.length) {
			if (lines[i].length == 0) { i++; continue; }

			auto header = lines[i++];
			auto parts = header.split(";")[0].split(",");
			dchar[] chars;

			foreach (p; parts)
				if (!p.empty)
					chars ~= cast(dchar)p[0];

			string[] bmpLines;
			while (i < lines.length && lines[i].length > 0 && !lines[i].endsWith(";"))
				bmpLines ~= lines[i++];

			if (bmpLines.length == 0) continue;

			Glyph g;
			g.width  = bmpLines[0].length.to!int;
			g.height = bmpLines.length.to!int;
			g.pixels.length = g.height;

			foreach (y; 0 .. g.height) {
				g.pixels[y].length = g.width;
				foreach (x; 0 .. g.width)
					g.pixels[y][x] = (bmpLines[y][x] == 'x');
			}

			foreach (c; chars)
				glyphs[c] = g;
		}
	}

	Surface getText(string text, Color color, uint fontSize) {
		int totalW = 0;
		foreach (dchar c; text) {
			auto g = (c in glyphs) ? glyphs[c] : glyphs['?'];
			totalW += fontSize * g.width / height;
		}

		auto outSurfSurf = new Surface(totalW, fontSize);
		outSurfSurf.fill(Color(0,0,0,0));

		int cx = 0;

		foreach (dchar c; text) {
			auto g = (c in glyphs) ? glyphs[c] : glyphs['?'];

			int scaleX = fontSize * g.width / height / g.width;
			int scaleY = fontSize / g.height;

			foreach (y; 0 .. g.height)
			foreach (x; 0 .. g.width) {
				if (!g.pixels[y][x]) continue;

				for (int sy = 0; sy < scaleY; sy++)
				for (int sx = 0; sx < scaleX; sx++) {
					outSurfSurf.setPixel(
						Point(cx + x * scaleX + sx,
							  y * scaleY + sy),
						color
					);
				}
			}

			cx += fontSize * g.width / height;
		}

		return outSurfSurf;
	}
}
