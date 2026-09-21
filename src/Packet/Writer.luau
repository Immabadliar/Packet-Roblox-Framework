--!strict

local Writer = {}
Writer.__index = Writer

export type Writer = typeof(setmetatable(
	{} :: {
		Values: { any },
	},
	Writer
))

function Writer.new(): Writer
	return setmetatable({
		Values = {},
	}, Writer)
end

function Writer:Write(value: any)
	table.insert(self.Values, value)
end

function Writer:Finish(): { any }
	return self.Values
end

return Writer
