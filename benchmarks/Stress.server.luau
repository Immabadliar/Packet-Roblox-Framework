--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Packet = require(ReplicatedStorage.Packet.PacketLibrary)

local Input = Packet.Define("__PacketBenchmark_Input", {
	Kind = Packet.Event,
	Direction = Packet.ClientToServer,
	RateLimit = 1000,
	Schema = {
		Sequence = Packet.u32,
		Value = Packet.f32,
	},
})

local Report = Packet.Define("__PacketBenchmark_Report", {
	Kind = Packet.Function,
	Direction = Packet.ClientToServer,
	RateLimit = 1000,
	Schema = {
		Attempted = Packet.u32,
		Duration = Packet.f32,
	},
	ResponseSchema = {
		Received = Packet.u32,
	},
})

local received = 0
local reportAttempted = 0
local reportDuration = 0
local heartbeatSamples: { number } = {}

Input:Listen(function()
	received += 1
end)

Report:Handle(function(_, payload)
	reportAttempted = payload.Attempted
	reportDuration = payload.Duration

	return {
		Received = received,
	}
end)

RunService.Heartbeat:Connect(function(deltaTime)
	table.insert(heartbeatSamples, deltaTime)

	if #heartbeatSamples < 600 then
		return
	end

	table.sort(heartbeatSamples)

	local total = 0

	for _, sample in heartbeatSamples do
		total += sample
	end

	local count = #heartbeatSamples
	local average = total / count
	local p95 = heartbeatSamples[math.max(1, math.ceil(count * 0.95))]
	local p99 = heartbeatSamples[math.max(1, math.ceil(count * 0.99))]
	local worst = heartbeatSamples[count]
	local dropped = math.max(reportAttempted - received, 0)

	print(string.format(
		"[Packet stress server] attempted=%d received=%d dropped=%d duration=%.2fs heartbeat_avg=%.3fms p95=%.3fms p99=%.3fms worst=%.3fms",
		reportAttempted,
		received,
		dropped,
		reportDuration,
		average * 1000,
		p95 * 1000,
		p99 * 1000,
		worst * 1000
	))

	table.clear(heartbeatSamples)
	received = 0
	reportAttempted = 0
end)
