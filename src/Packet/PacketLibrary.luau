--!strict

const PacketObject = require('./Packet')
const Codec = require('./Codec')

local Packet = {}

Packet.Define = PacketObject.Define
Packet.Get = PacketObject.Get
Packet.Exists = PacketObject.Exists

Packet.u8 = Codec.u8
Packet.u16 = Codec.u16
Packet.u32 = Codec.u32

Packet.i8 = Codec.i8
Packet.i16 = Codec.i16
Packet.i32 = Codec.i32

Packet.f32 = Codec.f32
Packet.f64 = Codec.f64

Packet.bool = Codec.bool
Packet.string = Codec.string

Packet.vector2 = Codec.vector2
Packet.vector3 = Codec.vector3
Packet.cframe = Codec.cframe
Packet.color3 = Codec.color3
Packet.instance = Codec.instance

Packet.Array = Codec.Array
Packet.Optional = Codec.Optional
Packet.Struct = Codec.Struct

Packet.ClientToServer = "ClientToServer"
Packet.ServerToClient = "ServerToClient"
Packet.Bidirectional = "Bidirectional"

Packet.Reliable = "Reliable"
Packet.Unreliable = "Unreliable"

return Packet
