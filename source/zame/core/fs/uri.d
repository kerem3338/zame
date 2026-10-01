module zame.core.fs.uri;

import std.string : indexOf, toLower, strip;
import std.ascii : isAlphaNum;

struct FsUri {
    string scheme;
    string path;

    bool isValid() const {
        return scheme.length > 0 && path.length > 0;
    }

    /// parse URI from string
    static FsUri parse(string uriString) {
        string s = uriString.strip();
        if (s.length == 0) {
            return FsUri("", "");
        }

        auto idx = s.indexOf("://");
        if (idx > 0) {
            string scheme = s[0 .. idx].toLower();
            string path = s[idx + 3 .. $];
            // Handle file:///C:/path -> C:/path
            if (path.length >= 3 && path[0] == '/' && isAlphaNum(path[1]) && path[2] == ':') {
                path = path[1 .. $];
            }
            return FsUri(scheme, path);
        }

        auto colonIdx = s.indexOf(':');
        // If colon exists, and it's not a single-letter Windows drive (e.g. "C:\" or "C:/")
        if (colonIdx > 1) {
            bool validScheme = true;
            foreach (c; s[0 .. colonIdx]) {
                if (!isAlphaNum(c) && c != '+' && c != '-' && c != '.') {
                    validScheme = false;
                    break;
                }
            }
            if (validScheme) {
                string scheme = s[0 .. colonIdx].toLower();
                string rest = s[colonIdx + 1 .. $];
                if (rest.length >= 2 && rest[0 .. 2] == "//") {
                    rest = rest[2 .. $];
                }
                return FsUri(scheme, rest);
            }
        }

        return FsUri("", s);
    }
    
    string toString() const {
        if (scheme.length > 0) {
            return scheme ~ "://" ~ path;
        }
        return path;
    }
}
