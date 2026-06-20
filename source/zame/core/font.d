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

interface Font {
	Size getSize(string text, int fontSize);
	Surface getText(string text, Color color, int fontSize);
	Surface getTextRich(string text, int fontSize, ubyte baseAlpha = 255);
	Surface getTextRich(Tuple!(string, Color)[] chunks, int fontSize, ubyte baseAlpha = 255);
	string[] wrapText(string text, int fontSize, int maxWidth);
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

class TrueTypeFont : Font {
	private ubyte[] data;
	private int unitsPerEm;
	private int indexToLocFormat; // 0 = short, 1 = long
	private int numGlyphs;
	
	// Table offsets
	private size_t headOffset;
	private size_t maxpOffset;
	private size_t locaOffset;
	private size_t glyfOffset;
	private size_t cmapOffset;
	private size_t hmtxOffset;
	private size_t hheaOffset;

	// Cache
	private int[dchar] charMap;
	
	private ushort readU16(size_t offset) {
		if (offset + 1 >= data.length) return 0;
		return bigEndianToNative!ushort(data[offset .. offset + 2].to!(ubyte[2]));
	}
	private short readI16(size_t offset) {
		if (offset + 1 >= data.length) return 0;
		return bigEndianToNative!short(data[offset .. offset + 2].to!(ubyte[2]));
	}
	private uint readU32(size_t offset) {
		if (offset + 3 >= data.length) return 0;
		return bigEndianToNative!uint(data[offset .. offset + 4].to!(ubyte[4]));
	}
	
	this(string path) {
		if (!exists(path)) throw new Exception("Font file not found: " ~ path);
		this.data = cast(ubyte[])read(path);
		parseTables();
	}
	
	private void parseTables() {
		// Offset Table
		// 0: scalars (u32)
		// 4: numTables (u16)
		ushort numTables = readU16(4);
		size_t offset = 12;
		
		for(int i=0; i<numTables; i++) {
			// Tag is 4 bytes
			 string tag = cast(string)data[offset .. offset+4];
			 size_t checkSum = readU32(offset+4);
			 size_t tableOffset = readU32(offset+8);
			 size_t length = readU32(offset+12);
			 
			 if (tag == "head") headOffset = tableOffset;
			 else if (tag == "maxp") maxpOffset = tableOffset;
			 else if (tag == "loca") locaOffset = tableOffset;
			 else if (tag == "glyf") glyfOffset = tableOffset;
			 else if (tag == "cmap") cmapOffset = tableOffset;
			 else if (tag == "hmtx") hmtxOffset = tableOffset;
			 else if (tag == "hhea") hheaOffset = tableOffset;
			 
			 offset += 16;
		}
		
		// Parse HEAD
		unitsPerEm = readU16(headOffset + 18);
		indexToLocFormat = readI16(headOffset + 50);
		
		// Parse CMAP (Format 4)
		parseCmap();
	}
	
	private void parseCmap() {
		ushort version_ = readU16(cmapOffset);
		ushort numTables = readU16(cmapOffset + 2);
		
		size_t selectedSubtable = 0;
		 
		// Find Windows Unicode BMP (3, 1) or Unicode (0, 3)
		size_t offset = cmapOffset + 4;
		for(int i=0; i<numTables; i++) {
			ushort platformId = readU16(offset);
			ushort encodingId = readU16(offset+2);
			uint suboffset = readU32(offset+4);
			
			if (platformId == 3 && encodingId == 1) { // Windows Unicode
				selectedSubtable = cmapOffset + suboffset;
				break;
			}
			 if (platformId == 0 && encodingId == 3) { // Unicode
				selectedSubtable = cmapOffset + suboffset;
				break;
			}
			offset += 8;
		}
		
		if (selectedSubtable == 0) return; // Not found
		
		ushort format = readU16(selectedSubtable);
		if (format == 4) {
			ushort length = readU16(selectedSubtable + 2);
			ushort segCountX2 = readU16(selectedSubtable + 6);
			int segCount = segCountX2 / 2;
			
			size_t endCodeOffset = selectedSubtable + 14;
			size_t startCodeOffset = endCodeOffset + segCountX2 + 2;
			size_t idDeltaOffset = startCodeOffset + segCountX2;
			size_t idRangeOffsetOffset = idDeltaOffset + segCountX2;
			
			// Map all printable characters including Turkish and extended Latin
			// This covers: Basic Latin, Latin-1 Supplement, Latin Extended-A, Latin Extended-B
			// Range includes: <, >, and all Turkish characters (ç, ğ, ı, ö, ş, ü, Ç, Ğ, İ, Ö, Ş, Ü)
			for (dchar c = 32; c < 592; c++) {
				 int glyphIndex = getGlyphIndexFormat4(c, segCount, endCodeOffset, startCodeOffset, idDeltaOffset, idRangeOffsetOffset, selectedSubtable);
				 if (glyphIndex != 0) charMap[c] = glyphIndex;
			}
			// Fallback
			charMap['?'] = getGlyphIndexFormat4('?', segCount, endCodeOffset, startCodeOffset, idDeltaOffset, idRangeOffsetOffset, selectedSubtable);
		} else if (format == 12) {
			 // Not implementing format 12 for now (needed for high unicode)
		}
	}
	
	private int getGlyphIndexFormat4(dchar c, int segCount, size_t endCodeOff, size_t startCodeOff, size_t idDeltaOff, size_t idRangeOff, size_t tableStart) {
		int code = cast(int)c;
		for(int i=0; i<segCount; i++) {
			 ushort endCode = readU16(endCodeOff + i*2);
			 if (code <= endCode) {
				 ushort startCode = readU16(startCodeOff + i*2);
				 if (code >= startCode) {
					 short idDelta = readI16(idDeltaOff + i*2);
					 ushort idRangeOffset = readU16(idRangeOff + i*2);
					 
					 if (idRangeOffset == 0) {
						 return (code + idDelta) & 0xFFFF;
					 } else {
						 // Obscure index calculation logic from spec
						 size_t addr = idRangeOff + i*2 + idRangeOffset + (code - startCode)*2;
						 ushort val = readU16(addr);
						 if (val == 0) return 0;
						 return (val + idDelta) & 0xFFFF;
					 }
				 }
				 break; // Sorted, so if code <= endCode and not >= startCode, it's not in this segment
			 }
		}
		return 0;
	}
	
	 private struct PointF { float x; float y; bool onCurve; }
	 
	 private PointF[][] getGlyphContours(int glyphIndex) {
		 if (locaOffset == 0 || glyfOffset == 0) return [];
		 
		 size_t glyphOff = 0;
		 if (indexToLocFormat == 0) {
			 glyphOff = readU16(locaOffset + glyphIndex * 2) * 2;
		 } else {
			 glyphOff = readU32(locaOffset + glyphIndex * 4);
		 }
		 
		  size_t nextOff = 0;
		  if (indexToLocFormat == 0) nextOff = readU16(locaOffset + (glyphIndex+1)*2) * 2;
		  else nextOff = readU32(locaOffset + (glyphIndex+1)*4);
		  
		  if (glyphOff == nextOff) return [];
		 
		 size_t start = glyfOffset + glyphOff;
		 short numContours = readI16(start);
		 
		 if (numContours < 0) {
			 // Composite glyph - render component glyphs
			 // Format: flags(u16), glyphIndex(u16), [arg1, arg2, ...]
			 // We'll implement a simplified version that just renders the base glyph
			 size_t offset = start + 10; // Skip glyph header
			 
			 PointF[][] allContours;
			 
			 while (true) {
				 ushort flags = readU16(offset);
				 ushort componentGlyphIndex = readU16(offset + 2);
				 offset += 4;
				 
				 // Read transformation arguments
				 short arg1, arg2;
				 if (flags & 0x0001) { // ARG_1_AND_2_ARE_WORDS
					 arg1 = readI16(offset);
					 arg2 = readI16(offset + 2);
					 offset += 4;
				 } else {
					 arg1 = cast(byte)data[offset];
					 arg2 = cast(byte)data[offset + 1];
					 offset += 2;
				 }
				 
				 if (flags & 0x0008) offset += 2;  // WE_HAVE_A_SCALE
				 if (flags & 0x0040) offset += 4;  // WE_HAVE_AN_X_AND_Y_SCALE  
				 if (flags & 0x0080) offset += 8;  // WE_HAVE_A_TWO_BY_TWO
				 
				 // Recursive get component contours
				 PointF[][] componentContours = getGlyphContours(componentGlyphIndex);
				 
				 // Apply transformation (Translation only for now)
				 // If ARGS_ARE_XY_VALUES (0x0002) is set, args are values. Otherwise they are point indices.
				 if (flags & 0x0002) {
					 float dx = cast(float)arg1;
					 float dy = cast(float)arg2;
					 
					 // If scaled, these values might be scaled too? 
					 // In standard TrueType, offset is in FUnits (unscaled).
					 // But if there is a scale component, does it apply to offset?
					 // Spec: "If bit 1 is set... the values are offsets... in FUnits."
					 
					 foreach(ref contour; componentContours) {
						 foreach(ref p; contour) {
							 p.x += dx;
							 p.y += dy;
						 }
					 }
				 }
				 
				 allContours ~= componentContours;
				 
				 if (!(flags & 0x0020)) break; // MORE_COMPONENTS flag
			 }
			 
			 return allContours;
		 }
		 
		 size_t endPtsOfContoursOff = start + 10;
		 ushort instructionLen = readU16(endPtsOfContoursOff + numContours * 2);
		 size_t flagsOff = endPtsOfContoursOff + numContours * 2 + 2 + instructionLen;
		 
		 int numPoints = readU16(endPtsOfContoursOff + (numContours-1)*2) + 1;
		 
		 PointF[] points = new PointF[](numPoints);
		 ubyte[] flags = new ubyte[](numPoints);
		 
		 size_t ptr = flagsOff;
		 for(int i=0; i<numPoints; i++) {
			 ubyte flag = data[ptr++];
			 flags[i] = flag;
			 if (flag & 8) {
				 ubyte count = data[ptr++];
				 for(int r=0; r<count; r++) {
					 i++;
					 flags[i] = flag;
				 }
			 }
		 }
		 
		 short currentX = 0;
		 for(int i=0; i<numPoints; i++) {
			 ubyte f = flags[i];
			 if (f & 2) {
				 ubyte val = data[ptr++];
				 currentX += (f & 16) ? val : -val;
			 } else {
				  if (!(f & 16)) {
					  short val = readI16(ptr);
					  ptr += 2;
					  currentX += val;
				  }
			 }
			 points[i].x = currentX;
			 points[i].onCurve = (f & 1) != 0;
		 }
		 
		 short currentY = 0;
		 for(int i=0; i<numPoints; i++) {
			 ubyte f = flags[i];
			 if (f & 4) {
				 ubyte val = data[ptr++];
				 currentY += (f & 32) ? val : -val;
			 } else {
				  if (!(f & 32)) { 
					  short val = readI16(ptr);
					  ptr += 2;
					  currentY += val;
				  }
			 }
			 points[i].y = currentY;
		 }
		 
		 PointF[][] contours;
		 int ptIdx = 0;
		  for(int c=0; c<numContours; c++) {
			  int endPt = readU16(endPtsOfContoursOff + c*2);
			  int count = endPt - ptIdx + 1;
			  contours ~= points[ptIdx .. ptIdx + count];
			  ptIdx = endPt + 1;
		  }
		 
		 return contours;
	 }

	private struct Edge {
		float x;
		float dx; // 1/slope
		int yMax;
		
		// Sorting: Primary Y-min (implicit by bucket), Secondary X, Tertiary dx
	}

	private struct Segment { PointF p0; PointF p1; }

	private Surface rasterizeGlyph(int glyphIndex, int fontSize, out int advanceWidth, out int yOffset) {
		float scale = cast(float)fontSize / unitsPerEm;
		
		ushort numHMetrics = readU16(hheaOffset + 34);
		int advW = 0;
		if (glyphIndex < numHMetrics) {
			advW = readU16(hmtxOffset + glyphIndex * 4);
		} else {
			advW = readU16(hmtxOffset + (numHMetrics-1) * 4);
		}
		advanceWidth = cast(int)(advW * scale);
		
		PointF[][] contours = getGlyphContours(glyphIndex);
		
		if (contours.length == 0) {
			// Empty glyph (space) - return transparent surface
			yOffset = 0;
			Surface empty = new Surface(max(1, advanceWidth), fontSize);
			empty.fill(Colors.transparent);
			return empty;
		}
		
		// Find bounds
		float minX = 10000, maxX = -10000, minY = 10000, maxY = -10000;
		foreach(c; contours) foreach(p; c) {
			minX = min(minX, p.x); maxX = max(maxX, p.x);
			minY = min(minY, p.y); maxY = max(maxY, p.y);
		}
		
		// Normalize bounds references
		float rawMinX = minX;
		float rawMaxX = maxX;
		float rawMinY = minY;
		float rawMaxY = maxY;
		
		int w = cast(int)ceil((maxX - minX) * scale) + 2;
		int h = cast(int)ceil((maxY - minY) * scale) + 2;
		
		// Calculate y offset for baseline alignment
		// In TTF, Y increases upward. We need to know how far below baseline this glyph extends
		yOffset = cast(int)(rawMaxY * scale);
		
		if (w < 1) w = 1; 
		if (h < 1) h = 1;
		
		Surface surf = new Surface(w, h);
		surf.fill(Colors.transparent);
		
		// Supersampling
		int supersample = 4;
		int bufW = w * supersample;
		int bufH = h * supersample;
		bool[] buffer = new bool[](bufW * bufH);
		
		// Edge List Logic
		// Transform all points first
		auto transform = (PointF p) {
			return PointF(
				(p.x - rawMinX) * scale * supersample + supersample,
				(rawMaxY - p.y) * scale * supersample + supersample,
				p.onCurve
			);
		};
		

		
		Segment[] edges;
		
		foreach(contour; contours) {
			 PointF prev = contour[$-1];
			 if (!prev.onCurve) {
				 if (contour[0].onCurve) prev = contour[$-1]; 
				 else prev = PointF((contour[$-1].x + contour[0].x)/2, (contour[$-1].y + contour[0].y)/2, true);
			 } else {
				 prev = contour[$-1];
			 }
			 
			 for(int i=0; i<contour.length; i++) {
				 PointF p = contour[i];
				 if (p.onCurve) {
					 edges ~= Segment(transform(prev), transform(p));
					 prev = p;
				 } else {
					 int nextIdx = cast(int)((i+1) % contour.length);
					 PointF next = contour[nextIdx];
					 
					 PointF target;
					 if (next.onCurve) {
						 target = next;
						 i++;
					 } else {
						 target = PointF((p.x + next.x)/2, (p.y + next.y)/2, true);
					 }
					 flattenCurve(edges, transform(prev), transform(p), transform(target));
					 prev = target;
				 }
			 }
		}

		// --- Rasterize Scanlines ---
		// Build Edge Table by scanline? array of arrays.
		// Or just one big list of edges and iterate Y?
		// Since H is small (fontSize * SS), array of lists is fine.
		
		struct EdgeIntersection {
			float x;
			int dir; // 1 for up, -1 for down
		}
		
		EdgeIntersection[][] activeEdges = new EdgeIntersection[][](bufH);
		
		foreach(e; edges) {
			PointF p0 = e.p0;
			PointF p1 = e.p1;
			
			if (abs(p0.y - p1.y) < 0.001) continue;
			
			int dir = (p1.y > p0.y) ? 1 : -1;
			if (p0.y > p1.y) { auto tmp = p0; p0 = p1; p1 = tmp; }
			
			// We want to sample at pixel CENTERS (y + 0.5)
			int yStart = cast(int)ceil(p0.y - 0.5f);
			int yEnd = cast(int)ceil(p1.y - 0.5f);
			
			if (yStart < 0) yStart = 0;
			if (yEnd > bufH) yEnd = bufH;
			
			float dx = (p1.x - p0.x) / (p1.y - p0.y);
			
			for(int y = yStart; y < yEnd; y++) {
				float sampleY = y + 0.5f;
				float x = p0.x + (sampleY - p0.y) * dx;
				activeEdges[y] ~= EdgeIntersection(x, dir);
			}
		}
		
		for(int y=0; y < bufH; y++) {
			 if (activeEdges[y].length == 0) continue;
			 
			 // Sort by X
			 activeEdges[y].sort!((a, b) => a.x < b.x);
			 
			 bool filling = false;
			 int lastX = 0;
			 
			 foreach(edge; activeEdges[y]) {
				 int x = cast(int)floor(edge.x + 0.5f);
				 
				 if (filling) {
					 int x0 = max(0, lastX);
					 int x1 = min(bufW, x);
					 for(int px = x0; px < x1; px++) {
						 buffer[y*bufW + px] = true;
					 }
				 }
				 
				 filling = !filling;
				 lastX = x;
			 }
		}
		
		// Downsample
		int totalPixels = 0;
		for(int y=0; y<h; y++) {
			for(int x=0; x<w; x++) {
				int sum = 0;
				for(int sy=0; sy<supersample; sy++) 
				for(int sx=0; sx<supersample; sx++) {
					 int by = y*supersample+sy;
					 int bx = x*supersample+sx;
					 if (by < bufH && bx < bufW && buffer[by*bufW + bx]) sum++;
				}
				
				int alpha = (sum * 255) / (supersample*supersample);
				if (alpha > 0) {
					surf.setPixel(Point(x,y), Color(255,255,255,cast(ubyte)alpha));
					totalPixels++;
				}
			}
		}
		
		return surf;
	}
	
	// Recursive Flatten
	private void flattenCurve(ref Segment[] edges, PointF p0, PointF c, PointF p1) {
		// Distance from c to line p0-p1
		float dx = p1.x - p0.x;
		float dy = p1.y - p0.y;
		float dist = abs(dy*c.x - dx*c.y + p1.x*p0.y - p1.y*p0.x) / sqrt(dx*dx + dy*dy);
		
		if (dist < 0.5f || (dx == 0 && dy == 0)) {
			edges ~= Segment(p0, p1);
			return;
		}
		
		PointF m0 = PointF((p0.x + c.x)/2, (p0.y + c.y)/2);
		PointF m1 = PointF((c.x + p1.x)/2, (c.y + p1.y)/2);
		PointF mm = PointF((m0.x + m1.x)/2, (m0.y + m1.y)/2);
		
		flattenCurve(edges, p0, m0, mm);
		flattenCurve(edges, mm, m1, p1);
	}
	
	// Interface Methods
	Size getSize(string text, int fontSize) {
		int w = 0;
		foreach(dchar c; text) {
			int idx = (c in charMap) ? charMap[c] : 0;
			if (idx == 0) continue;
			
			 // Very rough metric estimate if not rasterizing
			float scale = cast(float)fontSize / unitsPerEm;
			ushort numHMetrics = readU16(hheaOffset + 34);
			int advW = (idx < numHMetrics) ? readU16(hmtxOffset + idx * 4) : readU16(hmtxOffset + (numHMetrics-1) * 4);
			w += cast(int)(advW * scale);
		}
		return Size(w, fontSize);
	}

	private struct CachedGlyph {
		Surface s;
		int adv;
		int yOff;
	}

	private CachedGlyph[string] glyphCache;

	Surface getText(string text, Color color, int fontSize) {
		if (text.length == 0) return new Surface(1, 1);

		// Get font metrics for baseline calculation
		short ascender = readI16(hheaOffset + 4);
		float scale = cast(float)fontSize / unitsPerEm;
		int baselineOffset = cast(int)(ascender * scale);

		// Rasterize each glyph
		CachedGlyph[] glyphs;
		int totalW = 0;
		int maxH = fontSize;

		foreach (dchar c; text) {
			int idx = (c in charMap) ? charMap[c] : 0;
			if (idx == 0 && c != ' ') idx = charMap.get('?', 0);

			string cacheKey = format("%d_%d", idx, fontSize);
			CachedGlyph g;

			if (auto p = cacheKey in glyphCache) {
				g = *p;
			} else {
				int adv = 0;
				int yOff = 0;
				Surface s = rasterizeGlyph(idx, fontSize, adv, yOff);
				g = CachedGlyph(s, adv, yOff);
				glyphCache[cacheKey] = g;
			}

			if (g.s.height > maxH) maxH = g.s.height;
			glyphs ~= g;
			totalW += g.adv;
		}

		if (totalW == 0) totalW = 1;
		Surface result = new Surface(totalW, cast(int)(fontSize * 1.5));
		result.fill(Colors.transparent);

		int x = 0;

		foreach (g; glyphs) {
			// Calculate Y position based on baseline
			int y = baselineOffset - g.yOff;
			result.blit(g.s, x, y, true);
			x += g.adv;
		}

		// Apply color globally
		foreach (ref p; result.rawData) {
			if (p.a > 0) {
				p.r = color.r; p.g = color.g; p.b = color.b;
				p.a = cast(ubyte)(p.a * color.a / 255);
			}
		}

		return result;
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
