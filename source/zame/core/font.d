module zame.core.font;

import std.conv;
import std.string;
import std.utf;
import std.file;
import std.array;
import std.typecons;
import std.traits;
import std.algorithm;
import std.math;
import std.bitmanip;
import std.system;
import zame.core.common;
import zame.core.graphics;

import arsd.ttf;

struct FontInfo {
    string name;
}

interface Font {
	Size getSize(string text, int fontSize);
	Surface getText(string text, Color color, int fontSize);
	Surface getTextRich(string text, int fontSize, ubyte baseAlpha = 255);
	Surface getTextRich(Tuple!(string, Color)[] chunks, int fontSize, ubyte baseAlpha = 255);
	string[] wrapText(string text, int fontSize, int maxWidth);
    FontInfo fontInfo();
}

class BitmapFont : Font {
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
		this.loadAtlas(atlasPath);
		this.readInfo(infoPath);
	}

    FontInfo fontInfo() {
        FontInfo f;
        f.name = this.name;
        return f;
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

	Size getSize(string text, int fontSize) {
		if (text.length == 0)
			return Size(0, 0);

		int nativeW = 0;
		foreach (dchar c; text) {
			auto g = (c in glyphs) ? glyphs[c] : glyphs['?'];
			nativeW += g.w;
		}

		float scale = safeScale(fontSize);

		int scaledW = cast(int)(nativeW * scale);
		int scaledH = fontSize;

		int count = text.length.to!int;
		if (count > 1) {
			int spacing = cast(int)(widthSpacing * scale);
			int avgGlyphW = scaledW / count;
			int maxSpacing = avgGlyphW / 4;
			if (spacing > maxSpacing)
				spacing = maxSpacing;

			if (spacing > 0)
				scaledW += spacing * (count - 1);
		}

		return Size(scaledW, scaledH);
	}


	private Surface renderNative(string text, Color color) {
		int w = 0;
		try {
			foreach (dchar c; text)
				w += (c in glyphs ? glyphs[c].w : glyphs['?'].w);
		} catch (Exception e) {
			// Skip invalid characters or stop
		}

		auto outSurf = new Surface(w, lineHeight);
		outSurf.fill(Color(0,0,0,0));

		int cx = 0;
		try {
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
		} catch (Exception e) {}

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

	Surface getTextRich(string text, int fontSize, ubyte baseAlpha = 255) {
		import std.typecons : tuple;
		Tuple!(string, Color)[] chunks;
		
		Color currentColor = Colors.white;
		string currentText = "";
		
		static Color[string] colorMap;
		if (colorMap.length == 0) {
			import std.traits : EnumMembers;
			import std.conv : to;
			static foreach (member; EnumMembers!Colors) {
				colorMap[member.to!string.toLower] = member;
			}
		}

		for (size_t i = 0; i < text.length; i++) {
			if (text[i] == '%' && i + 1 < text.length) {
				size_t j = i + 1;
				while (j < text.length && text[j] != '%') j++;
				
				if (j < text.length) {
					string tag = text[i+1 .. j].toLower;
					if (currentText.length > 0) chunks ~= tuple(currentText, currentColor);
					currentText = "";
					
					if (tag == "reset") {
						currentColor = Colors.white;
					} else if (auto p = tag in colorMap) {
						currentColor = *p;
					}
					i = j;
					continue;
				}
			}
			currentText ~= text[i];
		}
		if (currentText.length > 0) chunks ~= tuple(currentText, currentColor);
		
		return getTextRich(chunks, fontSize, baseAlpha);
	}

	Surface getTextRich(Tuple!(string, Color)[] chunks, int fontSize, ubyte baseAlpha = 255) {
		if (chunks.length == 0) return new Surface(1, 1);
		
		Surface[] surfaces;
		int totalW = 0;
		int maxH = fontSize;
		
		foreach (chunk; chunks) {
			Color chunkColor = chunk[1];
			if (baseAlpha != 255) {
				chunkColor.a = cast(ubyte)(chunkColor.a * baseAlpha / 255);
			}
			Surface s = getText(chunk[0], chunkColor, fontSize);
			surfaces ~= s;
			totalW += s.width;
		}
		
		auto outSurf = new Surface(totalW, maxH);
		outSurf.fill(Color(0,0,0,0));
		
		int cx = 0;
		foreach (s; surfaces) {
			outSurf.blit(s, cx, 0, true);
			cx += s.width;
		}
		
		return outSurf;
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

	string[] wrapText(string text, int fontSize, int maxWidth) {
		import std.string : split;
		string[] lines;
		string[] words = text.split(" ");
		string currentLine = "";
		
		foreach (word; words) {
			string testLine = currentLine.length == 0 ? word : currentLine ~ " " ~ word;
			Size s = getSize(testLine, fontSize);
			if (s.w > maxWidth && currentLine.length > 0) {
				lines ~= currentLine;
				currentLine = word;
			} else {
				currentLine = testLine;
			}
		}
		
		if (currentLine.length > 0) lines ~= currentLine;
		return lines;
	}
}

class GenericBitmapFont : Font {
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
    
    FontInfo fontInfo() {
        FontInfo f;
        f.name = this.name;
        return f;
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

	Size getSize(string text, int fontSize) {
		if (text.length == 0)
			return Size(0, 0);

		int totalW = 0;

		foreach (dchar c; text) {
			auto g = (c in glyphs) ? glyphs[c] : glyphs['?'];
			totalW += fontSize * g.width / height;
		}

		return Size(totalW, fontSize);
	}


	Surface getText(string text, Color color, int fontSize) {
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

	Surface getTextRich(string text, int fontSize, ubyte baseAlpha = 255) {
		return getText(text, Colors.white, fontSize);
	}

	Surface getTextRich(Tuple!(string, Color)[] chunks, int fontSize, ubyte baseAlpha = 255) {
		return new Surface(1, 1);
	}

	string[] wrapText(string text, int fontSize, int maxWidth) {
		import std.string : split;
		string[] lines;
		string[] words = text.split(" ");
		string currentLine = "";
		
		foreach (word; words) {
			string testLine = currentLine.length == 0 ? word : currentLine ~ " " ~ word;
			Size s = getSize(testLine, fontSize);
			if (s.w > maxWidth && currentLine.length > 0) {
				lines ~= currentLine;
				currentLine = word;
			} else {
				currentLine = testLine;
			}
		}
		
		if (currentLine.length > 0) lines ~= currentLine;
		return lines;
	}
}

// TrueTypeFont is finally working :)
class TrueTypeFont : Font {
    private TtfFont font;
    private string fontPath;
    
    private struct CachedItem {
        Surface surface;
        Size size;
    }
    private CachedItem[string] cache;
    
    this(string path) {
        if (!exists(path)) throw new Exception("Font file not found: " ~ path);
        this.fontPath = path;
        this.font = TtfFont(cast(ubyte[]) read(path));
    }
    
    this(TtfFont font) {
        this.font = font;
        this.fontPath = ":memory:";
    }
    
    FontInfo fontInfo() {
        FontInfo f;
        f.name = this.fontPath; // dirty little hack
        return f;
    }
    
    Size getSize(string text, int fontSize) {
        if (text.length == 0) return Size(0, 0);
        
        string key = text ~ "_" ~ fontSize.to!string;
        if (auto p = key in cache) {
            return p.size;
        }
        
        int width, height;
        font.getStringSize(text, fontSize, width, height);
        Size size = Size(width, height);
        
        cache[key] = CachedItem(null, size);
        return size;
    }
    
    Surface getText(string text, Color color, int fontSize) {
        if (text.length == 0) {
            auto empty = new Surface(1, 1);
            empty.fill(Colors.transparent);
            return empty;
        }
        
        string key = text ~ "_" ~ fontSize.to!string;
        
        if (auto p = key in cache) {
            if (p.surface !is null && color == Colors.white) {
                return p.surface;
            }
        }
        
        int width, height;
        auto bitmap = font.renderString(text, fontSize, width, height);
        
        if (width == 0 || height == 0) {
            auto empty = new Surface(1, 1);
            empty.fill(Colors.transparent);
            return empty;
        }
        
        auto surf = new Surface(width, height);
        surf.fill(Colors.transparent);
        
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                ubyte alpha = bitmap[y * width + x];
                if (alpha > 0) {
                    Color pixel = Color(color.r, color.g, color.b,
                        cast(ubyte)(color.a * alpha / 255));
                    surf.setPixel(Point(x, y), pixel);
                }
            }
        }
        
        if (color == Colors.white) {
            cache[key] = CachedItem(surf, Size(width, height));
        }
        
        return surf;
    }
    
    Surface getTextRich(string text, int fontSize, ubyte baseAlpha = 255) {
        import std.typecons : tuple;
        Tuple!(string, Color)[] chunks;
        
        Color currentColor = Colors.white;
        string currentText = "";
        
        static Color[string] colorMap;
        if (colorMap.length == 0) {
            import std.traits : EnumMembers;
            import std.conv : to;
            static foreach (member; EnumMembers!Colors) {
                colorMap[member.to!string.toLower] = member;
            }
        }
        
        for (size_t i = 0; i < text.length; i++) {
            if (text[i] == '%' && i + 1 < text.length) {
                size_t j = i + 1;
                while (j < text.length && text[j] != '%') j++;
                
                if (j < text.length) {
                    string tag = text[i+1 .. j].toLower;
                    if (currentText.length > 0) chunks ~= tuple(currentText, currentColor);
                    currentText = "";
                    
                    if (tag == "reset") {
                        currentColor = Colors.white;
                    } else if (auto p = tag in colorMap) {
                        currentColor = *p;
                    }
                    i = j;
                    continue;
                }
            }
            currentText ~= text[i];
        }
        if (currentText.length > 0) chunks ~= tuple(currentText, currentColor);
        
        return getTextRich(chunks, fontSize, baseAlpha);
    }
    
    Surface getTextRich(Tuple!(string, Color)[] chunks, int fontSize, ubyte baseAlpha = 255) {
        if (chunks.length == 0) {
            auto empty = new Surface(1, 1);
            empty.fill(Colors.transparent);
            return empty;
        }
        
        Surface[] surfaces;
        int totalW = 0;
        int maxH = 0;
        
        foreach (chunk; chunks) {
            Color chunkColor = chunk[1];
            if (baseAlpha != 255) {
                chunkColor.a = cast(ubyte)(chunkColor.a * baseAlpha / 255);
            }
            Surface s = getText(chunk[0], chunkColor, fontSize);
            surfaces ~= s;
            totalW += s.width;
            if (s.height > maxH) maxH = s.height;
        }
        
        if (maxH == 0) maxH = fontSize;
        auto outSurf = new Surface(totalW, maxH);
        outSurf.fill(Colors.transparent);
        
        int cx = 0;
        foreach (s; surfaces) {
            int y = (maxH - s.height) / 2;
            outSurf.blit(s, cx, y, true);
            cx += s.width;
        }
        
        return outSurf;
    }
    
    string[] wrapText(string text, int fontSize, int maxWidth) {
        import std.string : split;
        string[] lines;
        string[] words = text.split(" ");
        string currentLine = "";
        
        foreach (word; words) {
            string testLine = currentLine.length == 0 ? word : currentLine ~ " " ~ word;
            Size s = getSize(testLine, fontSize);
            if (s.w > maxWidth && currentLine.length > 0) {
                lines ~= currentLine;
                currentLine = word;
            } else {
                currentLine = testLine;
            }
        }
        
        if (currentLine.length > 0) lines ~= currentLine;
        return lines;
    }
    
    void clearCache() {
        cache.clear();
    }
}