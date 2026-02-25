module zame.core.file;

import zame.core.platform;

string getDirSeperator() {
	version(Windows) {
		return "\\";
	} else version(Linux) {
		return "/";
	} else {
		return "/";
	}
}

