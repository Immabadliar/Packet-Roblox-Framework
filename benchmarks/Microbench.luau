--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packet = require(ReplicatedStorage.Packet.PacketLibrary)
local Codec = require(ReplicatedStorage.Packet.Codec)
local Reader = require(ReplicatedStorage.Packet.Reader)
local Writer = require(ReplicatedStorage.Packet.Writer)

local ITERATIONS = 10000

local function measure(name: string, iterations: number, callback: () -> ())
	for _ = 1, math.min(iterations, 1000) do
		callback()
	end

	local started = os.clock()

	for _ = 1, iterations do
		callback()
	end

	local elapsed = os.clock() - started
	local perOperation = elapsed / iterations
	local operationsPerSecond = if elapsed > 0 then iterations / elapsed else math.huge

	print(string.format(
		"[Packet benchmark] %-24s total=%.6fs per=%.3fus ops/s=%.0f",
		name,
		elapsed,
		perOperation * 1e6,
		operationsPerSecond
	))
end

local schema = {
	Id = Packet.u32,
	Amount = Packet.f32,
	Enabled = Packet.bool,
	Name = Packet.string,
	Position = Packet.vector3,
}

local payload = {
	Id = 123456,
	Amount = 12.5,
	Enabled = true,
	Name = "benchmark",
	Position = Vector3.new(1, 2, 3),
}

local function validateSchema()
	for field, codec in schema do
		if not codec.Validate(payload[field]) then
			error(`Schema validation failed for {field}`)
		end
	end
end

local function encodeSchema(): { any }
	local writer = Writer.new()

	for field, codec in schema do
		codec.Encode(writer, payload[field])
	end

	return writer:Finish()
end

local encoded = encodeSchema()

local function decodeSchema()
	local reader = Reader.new(encoded)
	local result = {}

	for field, codec in schema do
		result[field] = codec.Decode(reader)
	end

	assert(reader:Remaining() == 0)
end

local packetName = `__PacketBenchmark_{math.floor(os.clock() * 1000000)}`
local packet = Packet.Define(packetName, {
	Schema = schema,
})

print("[Packet benchmark] starting")
measure("schema validation", ITERATIONS, validateSchema)
measure("encoding", ITERATIONS, encodeSchema)
measure("decoding", ITERATIONS, decodeSchema)
measure("encode plus decode", ITERATIONS, function()
	local values = encodeSchema()
	local reader = Reader.new(values)

	for field, codec in schema do
		codec.Decode(reader)
	end
end)
measure("Packet.Get", ITERATIONS, function()
	assert(Packet.Get(packetName) == packet)
end)
measure("Packet.Exists", ITERATIONS, function()
	assert(Packet.Exists(packetName))
end)

print("[Packet benchmark] completed")
