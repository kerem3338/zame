module zame.core.device;

import std.format : format;
import zame.core.common;

enum DeviceType {
	unknown,
	computer,       /// A Computer
	tablet,         /// Tablet
	phone,          /// Mobile phone
	console,        /// Game console
	display,        /// External monitor / display
	keyboard,       /// Physical / virtual keyboard
	mouse,          /// Pointing device
	gamepad,        /// Game controller / joystick
	touchscreen,    /// Touch panel
	pen,            /// Stylus / pen input
	sensor,         /// Accelerometer, gyroscope, etc.
	audioInput,     /// Microphone / etc.
	audioOutput,    /// Speaker / headphones
}

enum DeviceConnectionState {
	unknown,
	connected,
	disconnected,
	connecting,
	busy,
	error,
}



/// Runtime status of a device instance.
struct DeviceStatus {
	DeviceConnectionState connection = DeviceConnectionState.unknown;
	/// last error (empty = no error)
	string errorMessage;
	/// platform-specific error code (0 = no error).
	int errorCode;

	@property bool isReady() const {
		return connection == DeviceConnectionState.connected;
	}

	string toString() const {
		if (errorMessage.length)
			return format("%s (%s, code %d)", connection, errorMessage, errorCode);
		return format("%s", connection);
	}
}

struct DeviceCapabilities {
	bool hasKeyboard;
	bool hasMouse;
	bool hasTouch;
	bool hasGamepad;
	bool hasRumble;
	bool hasGyroscope;
	bool hasAccelerometer;
	bool hasMultiTouch;
	uint maxTouchPoints;
}

abstract class IDevice {
	/// Display name of the device
	abstract string           name()         @property;
	/// Broad category.
	abstract DeviceType       type()         @property;
	/// Current connection / operational status.
	abstract DeviceStatus     status()       @property;
	/// Feature flags for this device.
	abstract DeviceCapabilities capabilities() @property;

	/// Called by DeviceManager once per frame.
	void update() {}
	/// Called when the device is removed or disconnected.
	void onDisconnect() {}
}

abstract class IInputDevice : IDevice {
	/// true if this device produced any input this frame.
	abstract bool hasInput() @property;
	/// reset per-frame transient state (called by DeviceManager).
	abstract void resetFrame();
}

struct DeviceInfo {
	// --- Operating System
	string osName;
	string osVersion;

	// --- CPU
	string cpuModel;
	uint   cpuCores;
	uint   cpuThreads;

	// --- Memory
	ulong  totalRam;
	ulong  availableRam;

	// --- GPU / Graphics
	string      gpuModel;
	GraphicsApi graphicsApi;
	ulong       gpuVram; 

	// --- Platform
	string platformName;
	uint   pointerBits;
	bool   isDebugBuild;

	string toString() const {
		return format(
			"DeviceInfo(os: %s %s, cpu: %s [%u cores / %u threads], ram: %u bytes, availableRam: %u bytes, gpu: %s, gpuVram: %u bytes, api: %s, platform: %s, pointerBits: %u, debug: %s)",
			osName, osVersion,
			cpuModel, cpuCores, cpuThreads,
			totalRam, availableRam,
			gpuModel, gpuVram,
			graphicsApi, platformName,
			pointerBits, isDebugBuild
		);
	}

	void fillBuildFlags() {
		pointerBits = cast(uint)(size_t.sizeof * 8);
		debug { isDebugBuild = true; }
	}
}


final class DeviceManager {
	private IDevice[] _devices;

	void register(IDevice dev) {
		foreach (d; _devices)
			if (d is dev) return;
		_devices ~= dev;
	}

	void unregister(IDevice dev) {
		import std.algorithm.mutation  : remove;
		import std.algorithm.searching : countUntil;
		auto idx = _devices.countUntil(dev);
		if (idx >= 0) {
			dev.onDisconnect();
			_devices = _devices.remove(idx);
		}
	}


	T get(T : IDevice)() {
		foreach (d; _devices)
			if (auto casted = cast(T)d) return casted;
		return null;
	}

	/// first device matching a DeviceType enum value (or null).
	IDevice getByType(DeviceType t) {
		foreach (d; _devices)
			if (d.type == t) return d;
		return null;
	}

	/// all devices matching a DeviceType enum value.
	IDevice[] getAllByType(DeviceType t) {
		IDevice[] result;
		foreach (d; _devices)
			if (d.type == t) result ~= d;
		return result;
	}

	/// all registered devices (read-only slice).
	@property const(IDevice[]) devices() const { return _devices; }

	/// number of registered devices.
	@property size_t count() const { return _devices.length; }

	/// Call once per frame: updates every device and resets transient
	/// input state for IInputDevice subclasses.
	void update() {
		foreach (dev; _devices) {
			dev.update();
			if (auto inp = cast(IInputDevice)dev)
				inp.resetFrame();
		}
	}
}