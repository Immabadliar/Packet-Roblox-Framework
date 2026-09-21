--!strict

local Registry = {}

local byName: { [string]: any } = {}
local byId: { [number]: any } = {}

local nextId = 1

function Registry.Register(name: string, packet: any): number
	assert(type(name) == "string", "Packet name must be a string")

	assert(name ~= "", "Packet name cannot be empty")

	assert(byName[name] == nil, `Packet "{name}" is already registered`)

	assert(nextId <= 65535, "Maximum packet count exceeded")

	local id = nextId

	nextId += 1

	byName[name] = packet
	byId[id] = packet

	return id
end

function Registry.FromName(name: string): any?
	return byName[name]
end

function Registry.FromId(id: number): any?
	return byId[id]
end

function Registry.Exists(name: string): boolean
	return byName[name] ~= nil
end

return Registry
