--!strict

local Reader = {}
Reader.__index = Reader

export type Reader = typeof(setmetatable(
	{} :: {
		Values: { any },
		Index: number,
	},
	Reader
))

function Reader.new(values: { any }): Reader
	return setmetatable({
		Values = values,
		Index = 1,
	}, Reader)
end

function Reader:Read(): any
	if self.Index > #self.Values then
		error("Attempted to read past the end of a packet", 2)
	end

	local value = self.Values[self.Index]

	self.Index += 1

	return value
end

function Reader:Remaining(): number
	return math.max(#self.Values - self.Index + 1, 0)
end

return Reader
