# Packet

Packet is a lightweight typed networking library for Roblox designed to make client server communication simple structured and safer without turning your project into a full framework

Packets are defined once with a direction transport and schema then used to send validated data between the client and server

```lua
local Attack = Packet.Define("Attack", {
	Direction = Packet.ClientToServer,
	Transport = Packet.Reliable,
	RateLimit = 15,

	Schema = {
		WeaponId = Packet.u8,
		Origin = Packet.vector3,
		Direction = Packet.vector3,
	},
})
```

## Features

* Typed packet schemas
* Client to server and server to client packets
* Bidirectional packets
* Reliable and unreliable transport
* Per packet rate limiting
* Runtime payload validation
* Numeric range validation
* NaN and infinity rejection
* String and array size limits
* Packet IDs
* Malformed packet rejection
* Listener connections
* One time listeners
* Server broadcasting
* Strict Luau support
* Lightweight API with no framework dependencies

## Installation

Place the `Packet` folder inside `ReplicatedStorage`

```text
ReplicatedStorage
└── Packet
    ├── Codec
    ├── PacketLibrary
    ├── Packet
    ├── Transport
    ├── Registry
    ├── Reader
    └── Writer
```

Then require the library

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packet = require(
	ReplicatedStorage.Packet.PacketLibrary
)
```

## Creating a Packet

Packets are created with `Packet.Define`

```lua
local Attack = Packet.Define("Attack", {
	Direction = Packet.ClientToServer,
	Transport = Packet.Reliable,
	RateLimit = 20,

	Schema = {
		WeaponId = Packet.u8,
		Position = Packet.vector3,
	}
})
```

Each packet receives a numeric packet ID automatically

```lua
print(Attack.Id)
```

## Sending Packets

### Client to Server

```lua
Attack:Send({
	WeaponId = 3,
	Position = Vector3.new(10, 5, 20),
})
```

The client does not need to specify a player because there is only one server

### Server to Client

```lua
Damage:Send({
	Amount = 25,
	Critical = false,
}, player)
```

### Broadcasting

The server can send a packet to every connected client

```lua
RoundStarted:Broadcast({
	Duration = 120,
})
```

## Receiving Packets

Use `Listen` to subscribe to a packet

### Server

```lua
Attack:Listen(function(player, data)
	print(player.Name)
	print(data.WeaponId)
	print(data.Position)
end)
```

### Client

```lua
Damage:Listen(function(data)
	print(data.Amount)
end)
```

`Listen` returns a connection

```lua
local connection = Damage:Listen(function(data)
	print(data.Amount)
end)

connection:Disconnect()
```

## RemoteFunctions

Use `Kind = Packet.Function` for request/response communication. The request uses `Schema`, and the returned value uses `ResponseSchema`.

```lua
local GetProfile = Packet.Define("GetProfile", {
	Kind = Packet.Function,
	Direction = Packet.ClientToServer,
	Schema = {
		UserId = Packet.u32,
	},
	ResponseSchema = {
		Name = Packet.string,
	},
})
```

Register a handler on the receiving side:

```lua
GetProfile:Handle(function(player, request)
	return {
		Name = player.Name,
	}
end)
```

Invoke it from the client:

```lua
local profile = GetProfile:Invoke({
	UserId = 123,
})
```

On the server, `Invoke` takes the target player as its second argument. RemoteFunction packets use reliable transport and cannot be broadcast.

## One Time Listeners

`Once` automatically disconnects after receiving the first packet

```lua
RoundStarted:Once(function(data)
	print(data.Duration)
end)
```

## Packet Directions

Packet supports three directions

```lua
Packet.ClientToServer
Packet.ServerToClient
Packet.Bidirectional
```

Example

```lua
local Purchase = Packet.Define("Purchase", {
	Direction = Packet.ClientToServer,

	Schema = {
		ItemId = Packet.u16,
	},
})
```

Packets received from an invalid direction are rejected before their listeners are called

## Transport

Packet supports reliable and unreliable networking

```lua
Packet.Reliable
Packet.Unreliable
```

Reliable transport should be used for information that must arrive

```lua
local Purchase = Packet.Define("Purchase", {
	Transport = Packet.Reliable,
})
```

Unreliable transport is useful for frequently changing state where losing an old update is acceptable

```lua
local Movement = Packet.Define("Movement", {
	Transport = Packet.Unreliable,

	Schema = {
		Position = Packet.vector3,
		Velocity = Packet.vector3,
	},
})
```

Internally Packet uses `RemoteEvent` for reliable packets and `UnreliableRemoteEvent` for unreliable packets

## Schemas

Schemas describe the expected structure of a packet payload

```lua
local Damage = Packet.Define("Damage", {
	Schema = {
		Amount = Packet.u16,
		Critical = Packet.bool,
	},
})
```

Invalid values are rejected

```lua
Damage:Send({
	Amount = "hello",
	Critical = false,
})
```

This does not satisfy the schema because `Amount` must be a `u16`

## Types

### Integers

```lua
Packet.u8
Packet.u16
Packet.u32

Packet.i8
Packet.i16
Packet.i32
```

Unsigned ranges

| Type | Minimum | Maximum |
| --- | ---: | ---: |
| `u8` | 0 | 255 |
| `u16` | 0 | 65,535 |
| `u32` | 0 | 4,294,967,295 |

Signed ranges

| Type | Minimum | Maximum |
| --- | ---: | ---: |
| `i8` | -128 | 127 |
| `i16` | -32,768 | 32,767 |
| `i32` | -2,147,483,648 | 2,147,483,647 |

### Floating Point

```lua
Packet.f32
Packet.f64
```

NaN and infinite values are rejected

### Roblox and Luau Types

```lua
Packet.bool
Packet.string

Packet.vector2
Packet.vector3

Packet.cframe
Packet.color3

Packet.instance
```

## Arrays

Use `Packet.Array` to create an array type

```lua
local Inventory = Packet.Define("Inventory", {
	Schema = {
		Items = Packet.Array(Packet.u16),
	},
})
```

Example payload

```lua
Inventory:Send({
	Items = { 4, 8, 15, 16, 23, 42 },
}, player)
```

Arrays are size limited to prevent excessively large network payloads

## Optional Values

Use `Packet.Optional` for values that may be `nil`

```lua
local PlayerState = Packet.Define("PlayerState", {
	Schema = {
		Target = Packet.Optional(Packet.instance),
	},
})
```

## Structs

Schemas can contain nested structures using `Packet.Struct`

```lua
local Position = Packet.Struct({
	X = Packet.f32,
	Y = Packet.f32,
	Z = Packet.f32,
})

local Update = Packet.Define("Update", {
	Schema = {
		Position = Position,
	},
})
```

## Rate Limiting

Client to server packets are rate limited independently for each player and packet

The default limit is

```text
60 packets per second
```

A custom limit can be provided when defining the packet

```lua
local Attack = Packet.Define("Attack", {
	Direction = Packet.ClientToServer,
	RateLimit = 15,

	Schema = {
		WeaponId = Packet.u8,
	},
})


## Security

Packet treats incoming client data as untrusted

Before a client packet reaches your listener Packet checks its packet ID transport direction rate limit decoding and schema

Malformed or invalid packets are dropped

Packet does not replace server authoritative game logic

For example

```lua
Purchase:Listen(function(player, data)
	local item = Items[data.ItemId]

	if item == nil then
		return
	end

	if player.leaderstats.Coins.Value < item.Price then
		return
	end

	-- Perform purchase
end)
```

Packet can verify that `ItemId` has the correct type and range

It cannot determine whether the player actually owns an item has enough currency is close enough to an object or is otherwise authorized to perform an action

Those checks should always remain server side

## Example

### Shared

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packet = require(
	ReplicatedStorage.Packet.PacketLibrary
)

local Packets = {}

Packets.Attack = Packet.Define("Attack", {
	Direction = Packet.ClientToServer,
	Transport = Packet.Reliable,
	RateLimit = 15,

	Schema = {
		WeaponId = Packet.u8,
		Origin = Packet.vector3,
		Direction = Packet.vector3,
	},
})

Packets.Damage = Packet.Define("Damage", {
	Direction = Packet.ServerToClient,

	Schema = {
		Amount = Packet.u16,
		Critical = Packet.bool,
	},
})

return Packets
```

### Client

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packets = require(ReplicatedStorage.Packets)

Packets.Attack:Send({
	WeaponId = 1,
	Origin = workspace.CurrentCamera.CFrame.Position,
	Direction = workspace.CurrentCamera.CFrame.LookVector,
})

Packets.Damage:Listen(function(data)
	print("Damage", data.Amount)
end)
```

### Server

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packets = require(ReplicatedStorage.Packets)

Packets.Attack:Listen(function(player, data)
	print(
		player.Name,
		data.WeaponId,
		data.Origin,
		data.Direction
	)

	Packets.Damage:Send({
		Amount = 25,
		Critical = false,
	}, player)
end)
```

## API

### `Packet.Define`

```lua
Packet.Define(name, config)
```

Creates and registers a packet

### `Packet.Get`

```lua
Packet.Get(name)
```

Returns a registered packet by name

### `Packet.Exists`

```lua
Packet.Exists(name)
```

Returns whether a packet with the given name exists

### `PacketObject:Send`

```lua
packet:Send(payload, player?)
```

Sends a packet

On the client the destination is the server

On the server `player` specifies the receiving client

### `PacketObject:Broadcast`

```lua
packet:Broadcast(payload)
```

Sends the packet to every client

Server only

### `PacketObject:Listen`

```lua
packet:Listen(callback)
```

Registers a listener and returns a disconnectable connection

### `PacketObject:Once`

```lua
packet:Once(callback)
```

Registers a listener that automatically disconnects after its first invocation

## Project Structure

```text
Packet
├── Codec
├── PacketLibrary
├── Packet
├── Transport
├── Registry
├── Reader
└── Writer
```

Each module has one primary responsibility

`PacketLibrary` exposes the public API

`Packet` handles packet definitions listeners validation and dispatch

`Codec` defines supported data types

`Transport` handles reliable and unreliable Roblox networking

`Registry` maps packet names and numeric IDs

`Writer` serializes packet values

`Reader` deserializes packet values

## Benchmarks

Packet is designed to keep local API and validation overhead low.

The following benchmarks were recorded in Roblox Studio using **100,000 iterations per test**. The comparison uses the same benchmark cases before and after the measured change.

| Operation | Previous | New | Change |
| --- | ---: | ---: | ---: |
| Packet property access | 92.19M ops/sec | **96.64M ops/sec** | **+4.8%** |
| `Packet.Get` | 24.78M ops/sec | **25.21M ops/sec** | **+1.8%** |
| `Packet.Exists` | 24.15M ops/sec | **24.67M ops/sec** | **+2.2%** |
| String validation | 22.30M ops/sec | **21.28M ops/sec** | **-4.6%** |
| `u16` validation | 19.94M ops/sec | **19.21M ops/sec** | **-3.7%** |
| `Vector3` validation | 13.30M ops/sec | **13.36M ops/sec** | **+0.4%** |

The largest gains were in packet property access and registry lookups. String and `u16` validation regressed in the new run, so those paths should not be treated as optimized. `Vector3` validation was effectively unchanged.

### Raw Results

```text
Packet.Get
Iterations: 100000
Total: 0.004036 seconds
Average: 0.040 µs
Throughput: 24,775,779 ops/sec

Packet.Exists
Iterations: 100000
Total: 0.004141 seconds
Average: 0.041 µs
Throughput: 24,145,841 ops/sec

Packet property access
Iterations: 100000
Total: 0.001085 seconds
Average: 0.011 µs
Throughput: 92,191,387 ops/sec

u16 validation
Iterations: 100000
Total: 0.005015 seconds
Average: 0.050 µs
Throughput: 19,941,372 ops/sec

string validation
Iterations: 100000
Total: 0.004485 seconds
Average: 0.045 µs
Throughput: 22,297,041 ops/sec

Vector3 validation
Iterations: 100000
Total: 0.007516 seconds
Average: 0.075 µs
Throughput: 13,304,595 ops/sec
```

> [!NOTE]
> These are local microbenchmarks and do not represent network throughput or packets per second across a Roblox client server connection. They measure operations such as registry lookup, property access, and schema validation.

> [!IMPORTANT]
> These results are from the current non-buffer implementation. Packet currently uses an intermediate value representation for serialization. Binary buffer serialization is planned and will be benchmarked separately once implemented.

Performance can vary depending on hardware, Roblox Studio, runtime conditions, and future Packet versions.

## Status

Packet is currently in development

The current Writer and Reader implementation uses an intermediate value representation

Binary buffer serialization is planned so packet schemas can be encoded directly into Roblox buffers with stricter byte limits and reduced network overhead

The public API is being designed so the serialization implementation can evolve without requiring major changes to game code