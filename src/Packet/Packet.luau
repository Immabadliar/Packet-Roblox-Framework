--!strict

const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const Registry = require('./Registry')
const Writer = require('./Writer')
const Reader = require('./Reader')
const Transport = require('./Transport')

local IS_SERVER = RunService:IsServer()

const DEFAULT_RATE_LIMIT = 60
const MAX_SCHEMA_FIELDS = 128
const DEBUG_DISABLE_RATE_LIMITER = false

export type Direction = "ClientToServer" | "ServerToClient" | "Bidirectional"

export type TransportType = "Reliable" | "Unreliable"

export type Kind = "Event" | "Function"

export type Schema = {
	[string]: any,
}

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Config = {
	Kind: Kind?,
	Direction: Direction?,
	Transport: TransportType?,
	Schema: Schema?,
	ResponseSchema: Schema?,
	RateLimit: number?,
}

export type PacketObject = {
	Name: string,
	Id: number,
	Kind: Kind,
	Direction: Direction,
	Transport: TransportType,
	Schema: Schema?,
	ResponseSchema: Schema?,
	RateLimit: number,

	Send: (self: PacketObject, payload: { [string]: any }, player: Player?) -> (),

	Broadcast: (self: PacketObject, payload: { [string]: any }) -> (),

	Invoke: (self: PacketObject, payload: { [string]: any }, player: Player?) -> { [string]: any },

	Listen: (self: PacketObject, callback: (...any) -> ()) -> Connection,

	Once: (self: PacketObject, callback: (...any) -> ()) -> Connection,

	Handle: (self: PacketObject, callback: (...any) -> { [string]: any }) -> Connection,
}

type RateState = {
	Tokens: number,
	Updated: number,
}

local Packet = {}
local PacketObject = {}

PacketObject.__index = PacketObject

local listeners: {
	[PacketObject]: { (...any) -> () },
} = {}

local handlers: {
	[PacketObject]: (...any) -> { [string]: any },
} = {}

local rateStates: {
	[Player]: {
		[number]: RateState,
	},
} = {}

local function checkRateLimit(player: Player, packet: PacketObject): boolean
	if DEBUG_DISABLE_RATE_LIMITER then
		return true
	end

	local playerStates = rateStates[player]

	if playerStates == nil then
		playerStates = {}
		rateStates[player] = playerStates
	end

	local now = os.clock()
	local limit = packet.RateLimit

	local state = playerStates[packet.Id]

	if state == nil then
		playerStates[packet.Id] = {
			Tokens = limit - 1,
			Updated = now,
		}

		return true
	end

	local elapsed = now - state.Updated

	state.Updated = now

	state.Tokens = math.min(limit, state.Tokens + elapsed * limit)

	if state.Tokens < 1 then
		return false
	end

	state.Tokens -= 1

	return true
end

if IS_SERVER then
	Players.PlayerRemoving:Connect(function(player)
		rateStates[player] = nil
	end)
end

local function validate(packet: PacketObject, payload: unknown, schema: Schema?): (boolean, string?)
	if schema == nil then
		return type(payload) == "table" and true or false, type(payload) == "table" and nil or "payload must be a table"
	end

	if type(payload) ~= "table" then
		return false, "payload must be a table"
	end

	for field, codec in schema do
		local value = (payload :: any)[field]

		if not codec.Validate(value) then
			return false, `invalid field "{field}", expected {codec.Name}`
		end
	end

	return true
end

local function encode(payload: { [string]: any }, schema: Schema?): { any }
	local writer = Writer.new()

	if schema == nil then
		writer:Write(payload)

		return writer:Finish()
	end

	for field, codec in schema do
		codec.Encode(writer, payload[field])
	end

	return writer:Finish()
end

local function decode(values: { any }, schema: Schema?): { [string]: any }
	local reader = Reader.new(values)

	if schema == nil then
		local value = reader:Read()

		if type(value) ~= "table" then
			error("Decoded packet payload must be a table")
		end

		return value
	end

	local result = {}

	for field, codec in schema do
		result[field] = codec.Decode(reader)
	end

	if reader:Remaining() ~= 0 then
		error("Packet contains unexpected trailing data")
	end

	return result
end

local function createConnection(packet: PacketObject, callback: (...any) -> ()): Connection
	local connection = {
		Connected = true,
	} :: Connection

	function connection:Disconnect()
		if not self.Connected then
			return
		end

		self.Connected = false

		local callbacks = listeners[packet]

		if callbacks == nil then
			return
		end

		local index = table.find(callbacks, callback)

		if index ~= nil then
			table.remove(callbacks, index)
		end

		if #callbacks == 0 then
			listeners[packet] = nil
		end
	end

	return connection
end

function PacketObject:Send(payload: { [string]: any }, player: Player?)
	local valid, reason = validate(self, payload, self.Schema)

	assert(valid, `Invalid payload for "{self.Name}": {reason}`)

	local encoded = encode(payload, self.Schema)

	if IS_SERVER then
		assert(self.Direction ~= "ClientToServer", `"{self.Name}" cannot be sent from the server`)

		assert(player ~= nil, `"{self.Name}" requires a Player`)

		Transport.SendClient(self.Transport, player, self.Id, encoded)

		return
	end

	assert(self.Direction ~= "ServerToClient", `"{self.Name}" cannot be sent from the client`)

	Transport.SendServer(self.Transport, self.Id, encoded)
end

function PacketObject:Invoke(payload: { [string]: any }, player: Player?): { [string]: any }
	assert(self.Kind == "Function", `"{self.Name}" is not a RemoteFunction packet`)

	local valid, reason = validate(self, payload, self.Schema)

	assert(valid, `Invalid payload for "{self.Name}": {reason}`)

	local encoded = encode(payload, self.Schema)
	local values: { any }

	if IS_SERVER then
		assert(self.Direction ~= "ClientToServer", `"{self.Name}" cannot be invoked from the server`)
		assert(player ~= nil, `"{self.Name}" requires a Player`)

		values = Transport.InvokeClient(player, self.Id, encoded)
	else
		assert(self.Direction ~= "ServerToClient", `"{self.Name}" cannot be invoked from the client`)

		values = Transport.InvokeServer(self.Id, encoded)
	end

	local response = decode(values, self.ResponseSchema)
	local responseValid, responseReason = validate(self, response, self.ResponseSchema)

	assert(responseValid, `Invalid response for "{self.Name}": {responseReason}`)

	return response
end

function PacketObject:Broadcast(payload: { [string]: any })
	assert(IS_SERVER, "Broadcast can only be called from the server")
	assert(self.Kind == "Event", `"{self.Name}" is not an event packet`)

	assert(self.Direction ~= "ClientToServer", `"{self.Name}" cannot be broadcast from the server`)

	local valid, reason = validate(self, payload, self.Schema)

	assert(valid, `Invalid payload for "{self.Name}": {reason}`)

	Transport.Broadcast(self.Transport, self.Id, encode(payload, self.Schema))
end

function PacketObject:Listen(callback: (...any) -> ()): Connection
	assert(type(callback) == "function", "Listener must be a function")

	local callbacks = listeners[self]

	if callbacks == nil then
		callbacks = {}
		listeners[self] = callbacks
	end

	table.insert(callbacks, callback)

	return createConnection(self, callback)
end

function PacketObject:Once(callback: (...any) -> ()): Connection
	local connection: Connection

	connection = self:Listen(function(...)
		connection:Disconnect()
		callback(...)
	end)

	return connection
end

function PacketObject:Handle(callback: (...any) -> { [string]: any }): Connection
	assert(self.Kind == "Function", `"{self.Name}" is not a RemoteFunction packet`)
	assert(type(callback) == "function", "Handler must be a function")
	assert(handlers[self] == nil, `"{self.Name}" already has a handler`)

	local packet = self

	handlers[self] = callback

	local connection = {
		Connected = true,
	} :: Connection

	function connection:Disconnect()
		if not self.Connected then
			return
		end

		self.Connected = false
		handlers[packet] = nil
	end

	return connection
end

function Packet.Define(name: string, config: Config?): PacketObject
	assert(
		type(name) == "string" and name ~= "",
		"Packet name must be a nonempty string"
	)

	assert(
		Registry.FromName(name) == nil,
		`Packet "{name}" already exists`
	)

	local settings: Config = config or {}

	local kind: Kind = settings.Kind or "Event"
	local direction: Direction = settings.Direction or "Bidirectional"
	local transport: TransportType = settings.Transport or "Reliable"
	local rateLimit: number = settings.RateLimit or DEFAULT_RATE_LIMIT

	assert(kind == "Event" or kind == "Function", "Invalid packet kind")

	if kind == "Function" then
		assert(transport == "Reliable", "RemoteFunction packets must use Reliable transport")
	end

	assert(
		direction == "ClientToServer"
			or direction == "ServerToClient"
			or direction == "Bidirectional",
		"Invalid packet direction"
	)

	assert(
		transport == "Reliable"
			or transport == "Unreliable",
		"Invalid packet transport"
	)

	assert(
		rateLimit == rateLimit
			and rateLimit >= 1
			and rateLimit <= 1000,
		"RateLimit must be between 1 and 1000"
	)

	if settings.Schema ~= nil then
		local fields = 0

		for _, codec in settings.Schema do
			fields += 1

			assert(
				type(codec) == "table"
					and type(codec.Validate) == "function"
					and type(codec.Encode) == "function"
					and type(codec.Decode) == "function",
				"Invalid codec in packet schema"
			)
		end

		assert(
			fields <= MAX_SCHEMA_FIELDS,
			"Packet schema has too many fields"
		)
	end

	if settings.ResponseSchema ~= nil then
		local fields = 0

		for _, codec in settings.ResponseSchema do
			fields += 1

			assert(
				type(codec) == "table"
					and type(codec.Validate) == "function"
					and type(codec.Encode) == "function"
					and type(codec.Decode) == "function",
				"Invalid codec in response schema"
			)
		end

		assert(
			fields <= MAX_SCHEMA_FIELDS,
			"Packet response schema has too many fields"
		)
	end

	local packet = setmetatable({
		Name = name,
		Id = 0,
		Kind = kind,
		Direction = direction,
		Transport = transport,
		Schema = settings.Schema,
		ResponseSchema = settings.ResponseSchema,
		RateLimit = rateLimit,
	}, PacketObject) :: any

	packet.Id = Registry.Register(name, packet)

	return packet
end

function Packet.Get(name: string): PacketObject?
	return Registry.FromName(name)
end

function Packet.Exists(name: string): boolean
	return Registry.Exists(name)
end

Transport.Connect(function(player, packetId, values, receivedTransport)
	local packet = Registry.FromId(packetId) :: PacketObject?

	if packet == nil then
		return
	end

	if packet.Transport ~= receivedTransport then
		return
	end

	if IS_SERVER then
		if player == nil then
			return
		end

		if packet.Direction == "ServerToClient" then
			return
		end

		if not checkRateLimit(player, packet) then
			return
		end
	else
		if packet.Direction == "ClientToServer" then
			return
		end
	end

	local success, payload = pcall(decode, values, packet.Schema)

	if not success then
		return
	end

	local valid = validate(packet, payload, packet.Schema)

	if not valid then
		return
	end

	local callbacks = listeners[packet]

	if callbacks == nil then
		return
	end

	for _, callback in callbacks do
		if IS_SERVER then
			task.spawn(callback, player, payload)
		else
			task.spawn(callback, payload)
		end
	end
end)

Transport.ConnectFunction(function(player, packetId, values)
	local packet = Registry.FromId(packetId) :: PacketObject?

	if packet == nil or packet.Kind ~= "Function" then
		error("Unknown RemoteFunction packet", 2)
	end

	if IS_SERVER then
		if player == nil or packet.Direction == "ServerToClient" then
			error("Invalid RemoteFunction direction", 2)
		end

		if not checkRateLimit(player, packet) then
			error("RemoteFunction rate limit exceeded", 2)
		end
	else
		if packet.Direction == "ClientToServer" then
			error("Invalid RemoteFunction direction", 2)
		end
	end

	local success, payload = pcall(decode, values, packet.Schema)

	if not success then
		error("Invalid RemoteFunction payload", 2)
	end

	local valid, reason = validate(packet, payload, packet.Schema)

	if not valid then
		error(`Invalid RemoteFunction payload: {reason}`, 2)
	end

	local handler = handlers[packet]

	if handler == nil then
		error(`No handler registered for "{packet.Name}"`, 2)
	end

	local handlerSuccess, response

	if IS_SERVER then
		handlerSuccess, response = pcall(handler, player, payload)
	else
		handlerSuccess, response = pcall(handler, payload)
	end

	if not handlerSuccess then
		error(response, 2)
	end

	local responseValid, responseReason = validate(packet, response, packet.ResponseSchema)

	if not responseValid then
		error(`Invalid RemoteFunction response: {responseReason}`, 2)
	end

	return encode(response, packet.ResponseSchema)
end)

return Packet
