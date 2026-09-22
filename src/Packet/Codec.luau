--!strict

const Writer = require('./Writer')
const Reader = require('./Reader')

export type Codec<T> = {
	Name: string,
	Validate: (value: unknown) -> boolean,
	Encode: (writer: Writer.Writer, value: T) -> (),
	Decode: (reader: Reader.Reader) -> T,
}

export type Schema = {
	[string]: Codec<any>,
}

local Codec = {}

const MAX_STRING_LENGTH = 4096
const MAX_ARRAY_LENGTH = 256

local function isFinite(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function integer(minimum: number, maximum: number): (unknown) -> boolean
	return function(value: unknown): boolean
		if not isFinite(value) then
			return false
		end

		local numberValue = value :: number

		return numberValue % 1 == 0 and numberValue >= minimum and numberValue <= maximum
	end
end

local function create<T>(name: string, validator: (value: unknown) -> boolean): Codec<T>
	return {
		Name = name,

		Validate = validator,

		Encode = function(writer, value)
			writer:Write(value)
		end,

		Decode = function(reader)
			return reader:Read()
		end,
	}
end

Codec.u8 = create("u8", integer(0, 255))
Codec.u16 = create("u16", integer(0, 65535))
Codec.u32 = create("u32", integer(0, 4294967295))

Codec.i8 = create("i8", integer(-128, 127))
Codec.i16 = create("i16", integer(-32768, 32767))
Codec.i32 = create("i32", integer(-2147483648, 2147483647))

Codec.f32 = create("f32", isFinite)
Codec.f64 = create("f64", isFinite)

Codec.bool = create("bool", function(value)
	return type(value) == "boolean"
end)

Codec.string = create("string", function(value)
	return type(value) == "string" and #value <= MAX_STRING_LENGTH
end)

Codec.vector2 = create("vector2", function(value)
	if typeof(value) ~= "Vector2" then
		return false
	end

	local vector = value :: Vector2

	return isFinite(vector.X) and isFinite(vector.Y)
end)

Codec.vector3 = create("vector3", function(value)
	if typeof(value) ~= "Vector3" then
		return false
	end

	local vector = value :: Vector3

	return isFinite(vector.X) and isFinite(vector.Y) and isFinite(vector.Z)
end)

Codec.cframe = create("cframe", function(value)
	if typeof(value) ~= "CFrame" then
		return false
	end

	local cframe = value :: CFrame

	for _, component in { cframe:GetComponents() } do
		if not isFinite(component) then
			return false
		end
	end

	return true
end)

Codec.color3 = create("color3", function(value)
	if typeof(value) ~= "Color3" then
		return false
	end

	local color = value :: Color3

	return isFinite(color.R) and isFinite(color.G) and isFinite(color.B)
end)

Codec.instance = create("instance", function(value)
	return typeof(value) == "Instance"
end)

function Codec.Optional<T>(codec: Codec<T>): Codec<T?>
	return {
		Name = `optional<{codec.Name}>`,

		Validate = function(value)
			return value == nil or codec.Validate(value)
		end,

		Encode = function(writer, value)
			writer:Write(value ~= nil)

			if value ~= nil then
				codec.Encode(writer, value)
			end
		end,

		Decode = function(reader)
			local exists = reader:Read()

			if type(exists) ~= "boolean" then
				error("Invalid optional marker", 2)
			end

			if not exists then
				return nil
			end

			return codec.Decode(reader)
		end,
	}
end

function Codec.Array<T>(codec: Codec<T>): Codec<{ T }>
	return {
		Name = `array<{codec.Name}>`,

		Validate = function(value)
			if type(value) ~= "table" then
				return false
			end

			local array = value :: { T }

			if #array > MAX_ARRAY_LENGTH then
				return false
			end

			for _, item in array do
				if not codec.Validate(item) then
					return false
				end
			end

			return true
		end,

		Encode = function(writer, value)
			local array = value :: { T }

			assert(#array <= MAX_ARRAY_LENGTH, "Array exceeds maximum packet array length")

			writer:Write(#array)

			for _, item: T in array do
				codec.Encode(writer, item)
			end
		end,

		Decode = function(reader)
			local length = reader:Read()

			if type(length) ~= "number" or length % 1 ~= 0 or length < 0 or length > MAX_ARRAY_LENGTH then
				error("Invalid packet array length", 2)
			end

			local count = length :: number
			local result: { T } = table.create(count)

			for index = 1, count do
				result[index] = codec.Decode(reader)
			end

			return result
		end,
	}
end

function Codec.Struct(schema: Schema): Codec<{ [string]: any }>
	return {
		Name = "struct",

		Validate = function(value)
			if type(value) ~= "table" then
				return false
			end

			local record = value :: { [string]: any }

			for field, fieldCodec in schema do
				if not fieldCodec.Validate(record[field]) then
					return false
				end
			end

			return true
		end,

		Encode = function(writer, value)
			local record = value :: { [string]: any }

			for field, fieldCodec in schema do
				fieldCodec.Encode(writer, record[field])
			end
		end,

		Decode = function(reader)
			local result: { [string]: any } = {}

			for field, fieldCodec in schema do
				result[field] = fieldCodec.Decode(reader)
			end

			return result
		end,
	}
end

return Codec
