module zame.core.network;

import std.socket;
import std.stdio;
import std.conv;
import std.datetime;
import std.datetime.stopwatch;
import zame.core.common;
import zame.core.log;
import core.sync.mutex;

// Network constants
enum MAX_PACKET_SIZE = 32768; // 32KB
enum MAX_PACKETS_PER_SECOND = 100;
enum RELIABLE_TIMEOUT_MS = 150;
enum MAX_RETRIES = 3;
enum MAX_PENDING_ACKS = 256;
enum SEQUENCE_WINDOW = 64;
enum CONNECTION_TIMEOUT_MS = 10000; // 10 seconds

// Special packet types
enum ubyte PACKET_TYPE_WELCOME = 255;
enum ubyte PACKET_TYPE_ACK = 253;
enum ubyte PACKET_TYPE_DISCONNECT = 254;

struct NetworkPacket {
	ubyte type;
	uint senderId;
	ubyte[] data;
}

// Reliability helper structures
private struct ReliablePacket {
	uint sequence;
	long timestamp; // milliseconds
	ubyte[] data;
	ubyte retryCount;
}

private struct ConnectionState {
	Address address;
	uint nextSequence;
	ulong receivedSeqBitfield; // Last 64 sequences
	uint baseSequence; // Base of the bitfield window
	ReliablePacket[uint] pendingAcks; // sequence -> packet
	long lastRecvTime;
	uint packetCount;
	long packetCountResetTime;
}

class NetworkClient {
	private UdpSocket socket;
	private uint id;
	private bool connected = false;
	private Address serverAddr;
	private ConnectionState state;
	private StopWatch timer;

	Logger logger = null;
    public int rtt = 0;

	this() {
		this(null);
		timer.start();
	}

	this(Logger logger) {
		this.logger = logger;
		if (this.logger is null) {
			this.logger = new Logger();
			this.logger.init();
		}
	}

	bool connect(string host, ushort port) {
		try {
			serverAddr = new InternetAddress(host, port);
			socket = new UdpSocket();
			socket.blocking = false;
			
			socket = new UdpSocket();
			socket.blocking = false;
			
			socket.bind(new InternetAddress("0.0.0.0", 0));
			logger.info("[NET CLIENT] Socket bound to local port: " ~ socket.localAddress.toPortString());
			
			connected = true;
			
			state.nextSequence = 1;
			state.baseSequence = 0;
			state.receivedSeqBitfield = 0;
			state.lastRecvTime = timer.peek().total!"msecs";
			state.packetCountResetTime = state.lastRecvTime;
			
			state.packetCountResetTime = state.lastRecvTime;
			
			logger.info("[NET CLIENT] Sending initial handshake packet...");
			ubyte[1] dummyData = [0];
			ubyte[] handshake = buildPacket(4, 0, dummyData[], 0, 0); // Type 4 = Input
			
			// Send multiple times to ensure delivery (UDP is unreliable)
			for (int i = 0; i < 3; i++) {
				try {
					socket.sendTo(handshake, serverAddr);
				} catch (Exception e) {
					logger.error("[NET CLIENT] Failed to send handshake: " ~ e.msg);
				}
				
				// Small delay between sends
				import core.thread;
				Thread.sleep(dur!"msecs"(10));
			}
			logger.info("[NET CLIENT] Handshake sent");
			
			return true;
		} catch (Exception e) {
			logger.error("[NET CLIENT] Network error: " ~ e.msg);
			return false;
		}
	}

	void disconnect() {
		if (connected) {
			// Send disconnect packet
			send(PACKET_TYPE_DISCONNECT, [], false);
			socket.close();
			connected = false;
		}
	}

	void send(ubyte type, const(ubyte)[] data, bool reliable = false) {
		if (!connected) return;
		if (data.length > MAX_PACKET_SIZE) {
			logger.warn("[NET CLIENT] Packet too large (" ~ data.length.to!string ~ " > " ~ MAX_PACKET_SIZE.to!string ~ "), dropping");
			return;
		}

		ubyte flags = reliable ? 1 : 0;
		uint sequence = reliable ? state.nextSequence++ : 0;

		ubyte[] buffer = buildPacket(type, id, data, flags, sequence);

		try {
			socket.sendTo(buffer, serverAddr);
			
			if (reliable) {
				if (state.pendingAcks.length >= MAX_PENDING_ACKS) {
					// Drop oldest
					uint oldestSeq = uint.max;
					foreach (seq; state.pendingAcks.keys) {
						if (seq < oldestSeq) oldestSeq = seq;
					}
					state.pendingAcks.remove(oldestSeq);
				}
				
				state.pendingAcks[sequence] = ReliablePacket(
					sequence,
					timer.peek().total!"msecs",
					buffer.dup,
					0
				);
			}
		} catch (Exception e) {
			logger.error("[NET CLIENT] Send error: " ~ e.msg);
			connected = false;
		}
	}

	NetworkPacket[] receive() {
		if (!connected) return [];

		NetworkPacket[] packets;
		ubyte[65536] tmp;

		while (true) {
			Address from;
			ptrdiff_t received;
			try {
				received = socket.receiveFrom(tmp, from);
			} catch (Exception e) {
				break;
			}

			if (received > 0) {
				state.lastRecvTime = timer.peek().total!"msecs";
				
				if (received < 13) continue; // Invalid packet
				
				auto pkt = parsePacket(tmp[0 .. received]);
				if (pkt.type == PACKET_TYPE_ACK) {
					handleAck(pkt.data);
				} else if (pkt.type == PACKET_TYPE_WELCOME) {
					logger.info("[NET CLIENT] Got WELCOME packet! ID = " ~ pkt.senderId.to!string);
					this.id = pkt.senderId;
				} else {
					packets ~= pkt;
				}
			} else if (received == Socket.ERROR) {
				if (wouldHaveBlocked()) break;
				else break;
			} else {
				break;
			}
		}

		return packets;
	}

	void update() {
		if (!connected) return;

		long now = timer.peek().total!"msecs";

		uint[] toRemove;
		foreach (seq, ref pkt; state.pendingAcks) {
			if (now - pkt.timestamp > RELIABLE_TIMEOUT_MS) {
				if (pkt.retryCount < MAX_RETRIES) {
					try {
						socket.sendTo(pkt.data, serverAddr);
						pkt.timestamp = now;
						pkt.retryCount++;
					} catch (Exception e) {
						logger.error("[NET CLIENT] Retransmit error: " ~ e.msg);
					}
				} else {
					logger.warn("[NET CLIENT] Packet " ~ seq.to!string ~ " dropped after " ~ MAX_RETRIES.to!string ~ " retries");
					toRemove ~= seq;
				}
			}
		}
		foreach (seq; toRemove) {
			state.pendingAcks.remove(seq);
		}
	}

	bool isConnected() { return connected; }
	uint getId() { return id; }

	private void handleAck(ubyte[] data) {
		if (data.length < 4) return;
		uint sequence = *cast(uint*)data.ptr;
        
        if (sequence in state.pendingAcks) {
            long now = timer.peek().total!"msecs";
            rtt = cast(int)(now - state.pendingAcks[sequence].timestamp);
            state.pendingAcks.remove(sequence);
        }
	}

	private NetworkPacket parsePacket(ubyte[] buffer) {
		if (buffer.length < 13) return NetworkPacket();

		ubyte type = buffer[0];
		uint senderId = *cast(uint*)&buffer[1];
		uint dataLen = *cast(uint*)&buffer[5];
		ubyte flags = buffer[9];
		uint sequence = *cast(uint*)&buffer[10];

		if (buffer.length < 14 + dataLen) return NetworkPacket();

		ubyte[] data = buffer[14 .. 14 + dataLen].dup;

		// Send ACK if reliable
		if (flags & 1) {
			// Check if duplicate
			if (!isDuplicate(sequence)) {
				markReceived(sequence);
				sendAck(sequence);
				return NetworkPacket(type, senderId, data);
			} else {
				// Duplicate, still send ACK but don't process
				sendAck(sequence);
				return NetworkPacket();
			}
		}

		return NetworkPacket(type, senderId, data);
	}

	private bool isDuplicate(uint sequence) {
		if (sequence < state.baseSequence) return true; // Too old
		if (sequence >= state.baseSequence + SEQUENCE_WINDOW) {
			// Advance window
			uint shift = sequence - state.baseSequence - SEQUENCE_WINDOW + 1;
			state.receivedSeqBitfield >>= shift;
			state.baseSequence += shift;
		}
		
		uint offset = sequence - state.baseSequence;
		return (state.receivedSeqBitfield & (1UL << offset)) != 0;
	}

	private void markReceived(uint sequence) {
		if (sequence >= state.baseSequence + SEQUENCE_WINDOW) {
			uint shift = sequence - state.baseSequence - SEQUENCE_WINDOW + 1;
			state.receivedSeqBitfield >>= shift;
			state.baseSequence += shift;
		}
		
		uint offset = sequence - state.baseSequence;
		state.receivedSeqBitfield |= (1UL << offset);
	}

	private void sendAck(uint sequence) {
		ubyte[] ackData;
		ackData.length = 4;
		*cast(uint*)ackData.ptr = sequence;
		
		ubyte[] buffer = buildPacket(PACKET_TYPE_ACK, 0, ackData, 0, 0);
		try {
			socket.sendTo(buffer, serverAddr);
		} catch (Exception e) {}
	}
}

class NetworkServer {
	private UdpSocket socket;
	private uint nextClientId = 1;
	private uint[] freeIds;
	private ConnectionState[string] connections;
	private string[uint] idToAddressStr;
	private uint[string] addressStrToId;
	private Mutex mutex;
	private StopWatch timer;

	Logger logger = null;

	void delegate(Address, ubyte, uint, ubyte[]) onPacket;
	void delegate(uint) onConnect;

	this(ushort port, Logger logger = null) {
		this.logger = logger;
		if (this.logger is null) {
			this.logger = new Logger();
			this.logger.init();
		}
		mutex = new Mutex();
		socket = new UdpSocket();
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.bind(new InternetAddress(port));
		socket.blocking = false;
		timer.start();
	}

	void disconnect(uint id) {
		mutex.lock();
		string* addrStr = id in idToAddressStr;
		if (!addrStr) {
			mutex.unlock();
			return;
		}
		
		string clientAddrStr = *addrStr;
		connections.remove(clientAddrStr);
		idToAddressStr.remove(id);
		addressStrToId.remove(clientAddrStr);
		freeIds ~= id;
		import std.algorithm : sort;
		sort(freeIds);
		mutex.unlock();
	}

	void update() {
		long now = timer.peek().total!"msecs";
		ubyte[65536] tmp;

		while (true) {
			Address from;
			ptrdiff_t received;
			try {
				received = socket.receiveFrom(tmp, from);
			} catch (Exception e) {
				break;
			}

			if (received > 0) {
				handleIncomingPacket(tmp[0 .. received], from, now);
			} else if (received == Socket.ERROR) {
				if (wouldHaveBlocked()) break;
				else break;
			} else {
				break;
			}
		}

		// Retransmit reliable packets and cleanup stale connections
		mutex.lock();
		string[] toRemove;
		foreach (addrStr, ref state; connections) {
			// Check timeout
			if (now - state.lastRecvTime > CONNECTION_TIMEOUT_MS) {
				toRemove ~= addrStr;
				continue;
			}

			// Retransmit
			uint[] acksToRemove;
			foreach (seq, ref pkt; state.pendingAcks) {
				if (now - pkt.timestamp > RELIABLE_TIMEOUT_MS) {
					if (pkt.retryCount < MAX_RETRIES) {
						try {
							socket.sendTo(pkt.data, state.address);
							pkt.timestamp = now;
							pkt.retryCount++;
						} catch (Exception e) {}
					} else {
						acksToRemove ~= seq;
					}
				}
			}
			foreach (seq; acksToRemove) {
				state.pendingAcks.remove(seq);
			}
		}

		// Remove stale connections
		foreach (addrStr; toRemove) {
			uint id = addressStrToId.get(addrStr, 0);
			if (id != 0) {
				logger.info("[NET SERVER] Client " ~ id.to!string ~ " timed out");
				ConnectionState* state = addrStr in connections;
				if (state && onPacket) onPacket(state.address, PACKET_TYPE_DISCONNECT, id, []);
				connections.remove(addrStr);
				idToAddressStr.remove(id);
				addressStrToId.remove(addrStr);
				freeIds ~= id;
				import std.algorithm : sort;
				sort(freeIds);
			}
		}
		mutex.unlock();
	}

	void broadcast(ubyte type, uint sid, const(ubyte)[] data, bool reliable = false) {
		mutex.lock();
		foreach (addrStr, ref state; connections) {
			sendToAddress(state.address, type, sid, data, reliable);
		}
		mutex.unlock();
	}

	void sendTo(uint targetId, ubyte type, const(ubyte)[] data, bool reliable = false) {
		mutex.lock();
		string* addrStr = targetId in idToAddressStr;
		if (addrStr) {
			ConnectionState* state = *addrStr in connections;
			if (state) {
				sendToAddress(state.address, type, 0, data, reliable);
			}
		}
		mutex.unlock();
	}

	size_t connectionCount() {
		mutex.lock();
		size_t count = connections.length;
		mutex.unlock();
		return count;
	}

	// Send directly to an address without requiring a connection (for server queries)
	void sendToAddressDirect(Address addr, ubyte type, const(ubyte)[] data) {
		if (data.length > MAX_PACKET_SIZE) return;
		
		ubyte[] buffer = buildPacket(type, 0, data, 0, 0);
		try {
			socket.sendTo(buffer, addr);
		} catch (Exception e) {
				logger.error("[NET SERVER] Send error: " ~ e.msg);
		}
	}

	private void handleIncomingPacket(ubyte[] buffer, Address from, long now) {
		// writeln("[SERVER] DEBUG: Packet received from ", from.toString(), " size=", buffer.length);
		
		if (buffer.length < 14) {
			logger.warn("[NET SERVER] Packet too small: " ~ buffer.length.to!string);
			return;
		}

		ubyte type = buffer[0];
		// if (type != 2 && type != 4) writeln("[SERVER] recv packet type: ", type, " from ", from.toString());
		
		uint senderId = *cast(uint*)&buffer[1];
		uint dataLen = *cast(uint*)&buffer[5];
		ubyte flags = buffer[9];
		uint sequence = *cast(uint*)&buffer[10];

		if (buffer.length < 14 + dataLen) {
			logger.warn("[NET SERVER] Packet data incomplete");
			return;
		}
		if (dataLen > MAX_PACKET_SIZE) {
			logger.warn("[NET SERVER] Packet too large");
			return;
		}

		ubyte[] data = buffer[14 .. 14 + dataLen].dup;

		string fromStr = from.toString();
		
		mutex.lock();
		
		// Get or create connection state
		ConnectionState* state = fromStr in connections;
		bool isNewConnection = (state is null);
		
		if (isNewConnection) {
			// New connection
			uint id;
			if (freeIds.length > 0) {
				id = freeIds[0];
				freeIds = freeIds[1 .. $];
			} else {
				id = nextClientId++;
			}

			ConnectionState newState;
			newState.address = from;
			newState.nextSequence = 1;
			newState.baseSequence = 0;
			newState.receivedSeqBitfield = 0;
			newState.lastRecvTime = now;
			newState.packetCountResetTime = now;
			newState.packetCount = 0;

			connections[fromStr] = newState;
			idToAddressStr[id] = fromStr;
			addressStrToId[fromStr] = id;
			state = fromStr in connections;

			logger.info("[NET SERVER] Client " ~ id.to!string ~ " connected from " ~ fromStr);
			
			// Send welcome
			sendToAddress(from, PACKET_TYPE_WELCOME, id, [], false);
			
			if (onConnect) onConnect(id);
		}

		// Rate limiting
		if (now - state.packetCountResetTime > 1000) {
			state.packetCount = 0;
			state.packetCountResetTime = now;
		}
		state.packetCount++;
		if (state.packetCount > MAX_PACKETS_PER_SECOND) {
			mutex.unlock();
			return;
		}

		state.lastRecvTime = now;
		uint clientId = addressStrToId[fromStr];

		mutex.unlock();

		// Handle ACK
		if (type == PACKET_TYPE_ACK) {
			handleAck(fromStr, data);
			return;
		}

		// Handle reliable packet
		if (flags & 1) {
			mutex.lock();
			bool isDup = isDuplicateServer(state, sequence);
			if (!isDup) {
				markReceivedServer(state, sequence);
			}
			mutex.unlock();
			
			sendAckToClient(from, sequence);
			
			if (isDup) return; // Don't process duplicate
		}

		// Process packet
		if (onPacket) onPacket(from, type, clientId, data);
	}

	private void handleAck(string fromStr, ubyte[] data) {
		if (data.length < 4) return;
		uint sequence = *cast(uint*)data.ptr;
		
		mutex.lock();
		ConnectionState* state = fromStr in connections;
		if (state) {
			state.pendingAcks.remove(sequence);
		}
		mutex.unlock();
	}

	private bool isDuplicateServer(ConnectionState* state, uint sequence) {
		if (sequence < state.baseSequence) return true;
		if (sequence >= state.baseSequence + SEQUENCE_WINDOW) {
			uint shift = sequence - state.baseSequence - SEQUENCE_WINDOW + 1;
			state.receivedSeqBitfield >>= shift;
			state.baseSequence += shift;
		}
		
		uint offset = sequence - state.baseSequence;
		return (state.receivedSeqBitfield & (1UL << offset)) != 0;
	}

	private void markReceivedServer(ConnectionState* state, uint sequence) {
		if (sequence >= state.baseSequence + SEQUENCE_WINDOW) {
			uint shift = sequence - state.baseSequence - SEQUENCE_WINDOW + 1;
			state.receivedSeqBitfield >>= shift;
			state.baseSequence += shift;
		}
		
		uint offset = sequence - state.baseSequence;
		state.receivedSeqBitfield |= (1UL << offset);
	}

	private void sendAckToClient(Address addr, uint sequence) {
		ubyte[] ackData;
		ackData.length = 4;
		*cast(uint*)ackData.ptr = sequence;
		
		ubyte[] buffer = buildPacket(PACKET_TYPE_ACK, 0, ackData, 0, 0);
		try {
			socket.sendTo(buffer, addr);
		} catch (Exception e) {}
	}

	private void sendToAddress(Address addr, ubyte type, uint sid, const(ubyte)[] data, bool reliable) {
		if (data.length > MAX_PACKET_SIZE) return;

		string addrStr = addr.toString();
		
		mutex.lock();
		ConnectionState* state = addrStr in connections;
		if (!state) {
			mutex.unlock();
			return;
		}

		ubyte flags = reliable ? 1 : 0;
		uint sequence = reliable ? state.nextSequence++ : 0;
		mutex.unlock();

		ubyte[] buffer = buildPacket(type, sid, data, flags, sequence);

		try {
			socket.sendTo(buffer, addr);
			
			if (reliable) {
				mutex.lock();
				if (state.pendingAcks.length >= MAX_PENDING_ACKS) {
					uint oldestSeq = uint.max;
					foreach (seq; state.pendingAcks.keys) {
						if (seq < oldestSeq) oldestSeq = seq;
					}
					state.pendingAcks.remove(oldestSeq);
				}
				
				state.pendingAcks[sequence] = ReliablePacket(
					sequence,
					timer.peek().total!"msecs",
					buffer.dup,
					0
				);
				mutex.unlock();
			}
		} catch (Exception e) {}
	}
}

// Helper function to build packet
private ubyte[] buildPacket(ubyte type, uint senderId, const(ubyte)[] data, ubyte flags, uint sequence) {
	ubyte[] buffer;
	buffer.length = 14 + data.length;
	
	buffer[0] = type;
	*cast(uint*)&buffer[1] = senderId;
	*cast(uint*)&buffer[5] = cast(uint)data.length;
	buffer[9] = flags;
	*cast(uint*)&buffer[10] = sequence;
	
	if (data.length > 0) {
		buffer[14 .. $] = data[];
	}
	
	return buffer;
}
