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

local levels = { 0, 1, 5, 10, 25, 50, 100 }
local levelIndex = 1
local levelDuration = 10
local levelStarted = os.clock()
local attempted = 0
local sequence = 0
local completed = false
local frameSamples: { number } = {}
local lastFrame = os.clock()

local function printLevel()
	local duration = os.clock() - levelStarted
	local sorted = table.clone(frameSamples)
	table.sort(sorted)

	local count = #sorted
	local total = 0

	for _, sample in sorted do
		total += sample
	end

	local average = if count > 0 then total / count else 0
	local p95 = if count > 0 then sorted[math.max(1, math.ceil(count * 0.95))] else 0
	local p99 = if count > 0 then sorted[math.max(1, math.ceil(count * 0.99))] else 0
	local worst = if count > 0 then sorted[count] else 0
	local result = Report:Invoke({
		Attempted = attempted,
		Duration = duration,
	})

	print(string.format(
		"[Packet stress client] rate=%d attempted=%d received=%d duration=%.2fs fps=%.2f frame_avg=%.3fms p95=%.3fms p99=%.3fms worst=%.3fms",
		levels[levelIndex],
		attempted,
		result.Received,
		duration,
		if average > 0 then 1 / average else 0,
		average * 1000,
		p95 * 1000,
		p99 * 1000,
		worst * 1000
	))
end

RunService.RenderStepped:Connect(function()
	if completed then
		return
	end

	local now = os.clock()
	table.insert(frameSamples, now - lastFrame)
	lastFrame = now

	local packetsPerFrame = levels[levelIndex]

	for _ = 1, packetsPerFrame do
		sequence += 1
		attempted += 1
		Input:Send({
			Sequence = sequence,
			Value = sequence,
		})
	end

	if now - levelStarted < levelDuration then
		return
	end

	printLevel()

	levelIndex += 1

	if levelIndex > #levels then
		print("[Packet stress client] completed")
		completed = true
		return
	end

	levelStarted = now
	attempted = 0
	table.clear(frameSamples)
end)
