--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")

export type TransportType = "Reliable" | "Unreliable"

local Transport = {}

local IS_SERVER = RunService:IsServer()

const MAX_PACKET_VALUES = 512

local folder: Folder
local reliable: RemoteEvent
local unreliable: UnreliableRemoteEvent
local functionRemote: RemoteFunction

if IS_SERVER then
	local existingFolder = ReplicatedStorage:FindFirstChild("__Packet")

	if existingFolder then
		assert(existingFolder:IsA("Folder"), "__Packet must be a Folder")

		folder = existingFolder
	else
		folder = Instance.new("Folder")
		folder.Name = "__Packet"
		folder.Parent = ReplicatedStorage
	end

	local reliableInstance = folder:FindFirstChild("Reliable")

	if reliableInstance then
		assert(reliableInstance:IsA("RemoteEvent"), "__Packet.Reliable must be a RemoteEvent")

		reliable = reliableInstance
	else
		reliable = Instance.new("RemoteEvent")
		reliable.Name = "Reliable"
		reliable.Parent = folder
	end

	local unreliableInstance = folder:FindFirstChild("Unreliable")

	if unreliableInstance then
		assert(unreliableInstance:IsA("UnreliableRemoteEvent"), "__Packet.Unreliable must be an UnreliableRemoteEvent")

		unreliable = unreliableInstance
	else
		unreliable = Instance.new("UnreliableRemoteEvent")
		unreliable.Name = "Unreliable"
		unreliable.Parent = folder
	end

	local functionInstance = folder:FindFirstChild("Function")

	if functionInstance then
		assert(functionInstance:IsA("RemoteFunction"), "__Packet.Function must be a RemoteFunction")

		functionRemote = functionInstance
	else
		functionRemote = Instance.new("RemoteFunction")
		functionRemote.Name = "Function"
		functionRemote.Parent = folder
	end
else
	folder = ReplicatedStorage:WaitForChild("__Packet") :: Folder

	reliable = folder:WaitForChild("Reliable") :: RemoteEvent

	unreliable = folder:WaitForChild("Unreliable") :: UnreliableRemoteEvent

	functionRemote = folder:WaitForChild("Function") :: RemoteFunction
end

local function validPacketId(value: unknown): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value <= 65535
end

local function validPayload(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end

	local payload = value :: { any }

	if #payload > MAX_PACKET_VALUES then
		return false
	end

	return true
end

function Transport.SendServer(transport: TransportType, packetId: number, payload: { any })
	assert(not IS_SERVER, "SendServer can only be called from the client")

	if transport == "Unreliable" then
		unreliable:FireServer(packetId, payload)
	else
		reliable:FireServer(packetId, payload)
	end
end

function Transport.SendClient(transport: TransportType, player: Player, packetId: number, payload: { any })
	assert(IS_SERVER, "SendClient can only be called from the server")

	assert(player.Parent ~= nil, "Cannot send packet to disconnected player")

	if transport == "Unreliable" then
		unreliable:FireClient(player, packetId, payload)
	else
		reliable:FireClient(player, packetId, payload)
	end
end

function Transport.Broadcast(transport: TransportType, packetId: number, payload: { any })
	assert(IS_SERVER, "Broadcast can only be called from the server")

	if transport == "Unreliable" then
		unreliable:FireAllClients(packetId, payload)
	else
		reliable:FireAllClients(packetId, payload)
	end
end

function Transport.InvokeServer(packetId: number, payload: { any }): { any }
	assert(not IS_SERVER, "InvokeServer can only be called from the client")

	return functionRemote:InvokeServer(packetId, payload)
end

function Transport.InvokeClient(player: Player, packetId: number, payload: { any }): { any }
	assert(IS_SERVER, "InvokeClient can only be called from the server")

	assert(player.Parent ~= nil, "Cannot invoke disconnected player")

	return functionRemote:InvokeClient(player, packetId, payload)
end

function Transport.Connect(callback: (Player?, number, { any }, TransportType) -> ())
	local function receive(transport: TransportType, player: Player?, packetId: unknown, payload: unknown)
		if not validPacketId(packetId) then
			return
		end

		if not validPayload(payload) then
			return
		end

		callback(player, packetId :: number, payload :: { any }, transport)
	end

	if IS_SERVER then
		reliable.OnServerEvent:Connect(function(player, packetId, payload)
			receive("Reliable", player, packetId, payload)
		end)

		unreliable.OnServerEvent:Connect(function(player, packetId, payload)
			receive("Unreliable", player, packetId, payload)
		end)

		return
	end

	reliable.OnClientEvent:Connect(function(packetId, payload)
		receive("Reliable", nil, packetId, payload)
	end)

	unreliable.OnClientEvent:Connect(function(packetId, payload)
		receive("Unreliable", nil, packetId, payload)
	end)
end

function Transport.ConnectFunction(callback: (Player?, number, { any }) -> { any })
	if IS_SERVER then
		functionRemote.OnServerInvoke = function(player, packetId, payload)
			return callback(player, packetId, payload)
		end
	else
		functionRemote.OnClientInvoke = function(packetId, payload)
			return callback(nil, packetId, payload)
		end
	end
end

return Transport
