--!native
--!strict
local Janitor = require(script.Parent.Parent.janitor)
local ServiceEventLinker = require(script.Parent.ServiceEventLinker)
local Types = require(script.Parent.Types)

local ComponentInstance = {}

type AttributeValue =
	string
	| boolean
	| number
	| UDim
	| UDim2
	| BrickColor
	| Color3
	| Vector2
	| Vector3
	| CFrame
	| NumberSequence
	| ColorSequence
	| NumberRange
	| Rect
	| Font;

export type Options = {
	Instance: Instance;
	PrimaryPart: BasePart?;
	Attributes: { [string]: AttributeValue };
}
export type ComponentInstance = Options & typeof(ComponentInstance)

function ComponentInstance.new(instance: Instance, def: Types.ComponentDef): typeof(ComponentInstance)
	local self = setmetatable({}, {
		__index = function(_, key)
			return ComponentInstance[key] or def[key]
		end
	})
	
	self._janitor = Janitor.new()
	self._properties = def
	
	self.Instance = instance
	self:AddToJanitor(instance)
	if instance:IsA("Model") then
		self.PrimaryPart = instance.PrimaryPart
	end
	
	self.Attributes = setmetatable({}, {
		__index = function(_, name: string)
			return instance:GetAttribute(name)
		end,
		__newindex = function(_, name: string, value)
			instance:SetAttribute(name, value)
		end
	})
	
	local function doesFunctionExist(name: string)
		return self[name] ~= nil and typeof(self[name]) == "function"
	end
	
	if doesFunctionExist("Initialize") then
		self:Initialize()
	end
	
	if doesFunctionExist("Update") then
		local linker = ServiceEventLinker()
		self:AddToJanitor(linker)
		
		local component = self
		function linker:Run_Heartbeat(dt: number)
			component:Update(dt)
			return
		end
	end
	
	return self :: any
end

function ComponentInstance:AddToJanitor<T>(object: T, methodName: (string | true)?, index: any?): T
	return (self._janitor.Add :: any)(self._janitor, object, methodName, index)
end

function ComponentInstance:Destroy(): nil
	if self._destroyed then return end
	self._destroyed = true
	
	self._janitor:Destroy()
	if self._properties.Destroy then
		self._properties.Destroy(self)
	end
	
	self._janitor = nil
	self._properties = nil
	self.Instance = nil
	self.Attributes = nil
	return
end

return ComponentInstance