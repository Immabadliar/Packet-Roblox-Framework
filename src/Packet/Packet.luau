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

export type Direction = "ClientToServer" | "ServerToClient" | "Bidirectional"

export type TransportType = "Reliable" | "Unreliable"

export type Schema = {
	[string]: any,
}

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Config = {
	Direction: Direction?,
	Transport: TransportType?,
	Schema: Schema?,
	RateLimit: number?,
}

export type PacketObject = {
	Name: string,
	Id: number,
	Direction: Direction,
	Transport: TransportType,
	Schema: Schema?,
	RateLimit: number,

	Send: (self: PacketObject, payload: { [string]: any }, player: Player?) -> (),

	Broadcast: (self: PacketObject, payload: { [string]: any }) -> (),

	Listen: (self: PacketObject, callback: (...any) -> ()) -> Connection,

	Once: (self: PacketObject, callback: (...any) -> ()) -> Connection,
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

local rateStates: {
	[Player]: {
		[number]: RateState,
	},
} = {}

local function checkRateLimit(player: Player, packet: PacketObject): boolean
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

local function validate(packet: PacketObject, payload: unknown): (boolean, string?)
	if packet.Schema == nil then
		return type(payload) == "table" and true or false, type(payload) == "table" and nil or "payload must be a table"
	end

	if type(payload) ~= "table" then
		return false, "payload must be a table"
	end

	for field, codec in packet.Schema do
		local value = (payload :: any)[field]

		if not codec.Validate(value) then
			return false, `invalid field "{field}", expected {codec.Name}`
		end
	end

	return true
end

local function encode(packet: PacketObject, payload: { [string]: any }): { any }
	local writer = Writer.new()

	if packet.Schema == nil then
		writer:Write(payload)

		return writer:Finish()
	end

	for field, codec in packet.Schema do
		codec.Encode(writer, payload[field])
	end

	return writer:Finish()
end

local function decode(packet: PacketObject, values: { any }): { [string]: any }
	local reader = Reader.new(values)

	if packet.Schema == nil then
		local value = reader:Read()

		if type(value) ~= "table" then
			error("Decoded packet payload must be a table")
		end

		return value
	end

	local result = {}

	for field, codec in packet.Schema do
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
	local valid, reason = validate(self, payload)

	assert(valid, `Invalid payload for "{self.Name}": {reason}`)

	local encoded = encode(self, payload)

	if IS_SERVER then
		assert(self.Direction ~= "ClientToServer", `"{self.Name}" cannot be sent from the server`)

		assert(player ~= nil, `"{self.Name}" requires a Player`)

		Transport.SendClient(self.Transport, player, self.Id, encoded)

		return
	end

	assert(self.Direction ~= "ServerToClient", `"{self.Name}" cannot be sent from the client`)

	Transport.SendServer(self.Transport, self.Id, encoded)
end

function PacketObject:Broadcast(payload: { [string]: any })
	assert(IS_SERVER, "Broadcast can only be called from the server")

	assert(self.Direction ~= "ClientToServer", `"{self.Name}" cannot be broadcast from the server`)

	local valid, reason = validate(self, payload)

	assert(valid, `Invalid payload for "{self.Name}": {reason}`)

	Transport.Broadcast(self.Transport, self.Id, encode(self, payload))
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

	local direction: Direction = settings.Direction or "Bidirectional"
	local transport: TransportType = settings.Transport or "Reliable"
	local rateLimit: number = settings.RateLimit or DEFAULT_RATE_LIMIT

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

	local packet = setmetatable({
		Name = name,
		Id = 0,
		Direction = direction,
		Transport = transport,
		Schema = settings.Schema,
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

	local success, payload = pcall(decode, packet, values)

	if not success then
		return
	end

	local valid = validate(packet, payload)

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

return Packet
