module zame.translation;

import zame.core.common;

import std.json;
import std.file;
import std.format;
import std.conv;
import std.stdio;
import std.variant;
import std.regex;
import std.array;
import std.typecons;

enum TranslationResult: int {
	ok = 0,
	text_not_founded = 1,
	key_not_founded = 1,
	language_not_founded = 2
}

version (Windows)
{
	import core.sys.windows.windows;
	import std.utf;

	enum LOCALE_NAME_MAX_LENGTH = 85;

	extern(Windows)
	BOOL GetUserDefaultLocaleName(
		LPWSTR lpLocaleName,
		int cchLocaleName
	);

	pragma(lib, "kernel32.lib");
}


class Language {
	string name;
	string localName;
	string langCode;
	string[string] texts;

	this(string name, string localName, string langCode) {
		this.name = name;
		this.localName = localName;
		this.langCode = langCode;
	}

	string getText(string key, Variant[] values = [], string defaultValue = "") {
		if (key !in texts) {
			return (defaultValue == "") ? key : defaultValue;
		}

		string raw = texts[key];
		if (values.length == 0) {
			return raw;
		}

		auto app = appender!string();
		auto re = regex(`%[-+ #0]*[\d\.]*[sdfxu%c]`);
		size_t lastPos = 0;
		size_t argIdx = 0;

		foreach (m; raw.matchAll(re)) {
			app.put(raw[lastPos .. m.pre.length]);
			string placeholder = m.hit;

			if (placeholder == "%%") {
				app.put("%");
			} else if (argIdx < values.length) {
				try {
					app.put(format(placeholder, values[argIdx]));
				} catch (Exception e) {
					app.put(values[argIdx].toString());
				}
				argIdx++;
			} else {
				app.put(placeholder);
			}
			lastPos = m.pre.length + m.hit.length;
		}
		app.put(raw[lastPos .. $]);
		return app.data;
	} 

	string tr(T...)(string key, T args) {
		Variant[] values;
		foreach (arg; args) {
			values ~= Variant(arg);
		}
		return getText(key, values);
	}
}


class TranslationManager {
	Language[string] languages;
	string searchLanguage = "en_US";

	this() {

	}

	Tuple!(TranslationResult, string) getText(string key, Variant[] values = [], string fallback = "") {
		if (searchLanguage !in languages) {
            return tuple(TranslationResult.language_not_founded, fallback != "" ? fallback : key);
        }
        
        auto lang = languages[searchLanguage];
        if (key !in lang.texts) {
            return tuple(TranslationResult.text_not_founded, fallback != "" ? fallback : key);
        }

        return tuple(TranslationResult.ok, lang.getText(key, values, fallback));
	}

	string tr(T...)(string key, T args) {
		Variant[] values;
		static foreach (arg; args) {
			values ~= Variant(arg);
		}
		return getText(key, values)[1];
	}

	Outcome!bool addNewLanguage(Language language, bool overrideLanguage = false) {
		if (language.langCode in languages && !overrideLanguage) {
			return failure!bool(Result.override_error, format("Language with code '%s' already exists.", language.langCode));
		}

		languages[language.langCode] = language;
		return success(true);
	}
}


Outcome!string getUserLocaleLanguage()
{
	version (Windows)
	{
		wchar[LOCALE_NAME_MAX_LENGTH] localeName;

		if (!GetUserDefaultLocaleName(localeName.ptr, localeName.length))
			return failure!string(Result.os_error);
		size_t len = 0;
		while (len < localeName.length && localeName[len] != 0)
			++len;

		string _localeName = toUTF8(localeName[0 .. len]);
		_localeName = _localeName.replace('-', '_');

		return success!string(_localeName);
	}
	else
	{
		return failure!string(platform_not_supported);
	}
}

Outcome!Language langFromFile(string filePath) {
	Tuple!(bool,string) hasRequiredKeys(string[] keys, JSONValue[string] root) {
		foreach (string key; keys) {
			if (!(key in root)) return tuple(false, key);
		}
		return tuple(true, "");
	}

	if (!filePath.exists) return failure!Language(Result.file_not_found, format("Language file '%s' doesnt exists.", filePath));
	JSONValue jsonData = parseJSON(readText(filePath));
	
	auto langInfoCheck = hasRequiredKeys(["info"], jsonData.get!(JSONValue[string]));
	if (!langInfoCheck[0]) {
		return failure!Language(Result.key_error, format("Required key 'info' has not been found in file '%s'", filePath));
	}

	string name, localName, langCode;
	auto langInfo = jsonData["info"].get!(JSONValue[string]);

	auto textsCheck = hasRequiredKeys(["texts"], jsonData.get!(JSONValue[string]));
	if (!textsCheck[0]) {
		return failure!Language(Result.key_error, format("Required value '%s' cannot be founded inside of provided language file", textsCheck[1]));
	}

	auto metaDatacheck = hasRequiredKeys(["name", "localName", "langCode"], langInfo);
	if (!metaDatacheck[0]) {
		return failure!Language(Result.key_error, format("Required value '%s' cannot be founded inside of provided 'info' value", metaDatacheck[1]));
	} else {
		name = langInfo["name"].get!string;
		localName = langInfo["localName"].get!string;
		langCode = langInfo["langCode"].get!string;
	}

	Language language = new Language(name, localName, langCode);
	foreach (string key, value; jsonData["texts"].object) {
		language.texts[key] = value.str;
	}
	return success!Language(language);
}