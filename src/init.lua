--!native
--!strict
local CollectionService = game:GetService("CollectionService")

local ComponentInstance = require(script.ComponentInstance)
local Array = require(script.Parent.Array)
local Types = require(script.Types)

_G.ComponentClasses = _G.ComponentClasses or Array.new("function")
local Component = {}
Component.__index = Component

export type Def = Types.ComponentDef
export type Component = typeof(Component) & {
	Name: string;
	LoadOrder: number?;
	OwnedComponents: typeof(Array.new("table"));
}

type InstanceGuard<T> = {
	PropertyName: string;
	Value: T;
}

function Component.Get(name: string): Component
	local component = _G.ComponentClasses
		:Find(function(component: () -> Component)
			return component().Name == name
		end)

	assert(component ~= nil, `Failed to get component: Component "{name}" does not exist!`)
	return component()
end

local COMPONENT_CACHE = {}
function Component.Load(module: ModuleScript): nil
	_G.ComponentClasses:Push(function()
		if COMPONENT_CACHE[module.Name] then
			return COMPONENT_CACHE[module.Name]
		end

		local success, result = pcall(require, module)
		if not success then
			error(`Failed to load {module:GetFullName()}: {result}`)
		end

		COMPONENT_CACHE[module.Name] = result
		return result
	end)
	return
end

function Component.LoadFolder(folder: Folder): nil
	for _, module: Instance in folder:GetDescendants() do
		if module:IsA("ModuleScript") then
			Component.Load(module)
		end
	end
	return
end

function Component.StartComponents(): nil
	local orderedComponents = _G.ComponentClasses:Sort(function(a: () -> Component, b: () -> Component)
		local aOrder = a().LoadOrder
		local bOrder = b().LoadOrder
		return if aOrder and bOrder then aOrder < bOrder else false
	end)

	for component: () -> Component in orderedComponents:Values() do
		component():_Start()
	end
	return
end

function Component.new(def: Types.ComponentDef, options: Types.ComponentOptions?)
	assert(def ~= nil, "Must provide a component definition.")
	assert(def.Name ~= nil, "Must provide Name property!")
	assert(typeof(def.Name) == "string", "Component name must be a string!")
	assert(#def.Name > 0, "Component name must have at least one character!")

	local self = setmetatable({}, Component)
	self.OwnedComponents = Array.new("table")
	self.Name = def.Name
	self.LoadOrder = def.LoadOrder
	self._def = def

	self._useTags = true
	if options and options.UseTags ~= nil then
		self._useTags = options.UseTags
	end

	return self
end

function Component:_Start(): nil
	task.spawn(function()
		if self._useTags then
			CollectionService:GetInstanceAddedSignal(self._def.Name):Connect(function(instance: Instance)
				self:Add(instance)
			end)
			CollectionService:GetInstanceRemovedSignal(self._def.Name):Connect(function(instance: Instance)
				self:Remove(instance, true)
			end)
	
			Array.new("Instance", CollectionService:GetTagged(self._def.Name))
				:ForEach(function(instance: Instance)
					self:Add(instance)
				end)
		end
	end)
	return
end

function Component:Find(instance: Instance): ComponentInstance.ComponentInstance?
	return self.OwnedComponents:Find(function(component: ComponentInstance.ComponentInstance)
		return component.Instance == instance
	end)
end

local validateGuards = nil
local function validateGuard<T>(componentName: string, instance: Instance, guard: InstanceGuard<T>, noError: boolean): nil
	local stackInfo = ` ({componentName} :> {instance:GetFullName()})`
	local invalidate: (msg: string) -> nil = if noError then warn else error
	
	if guard.PropertyName == "Children" then
		for childName, childGuards: Types.Guards in guard.Value :: any do
			local child = instance:WaitForChild(childName, 7)
			if not child then
				return invalidate(`Child "{childName}" does not exist on {instance:GetFullName()}!{stackInfo}`)
			end
			validateGuards(componentName, child, childGuards, true)
		end
	elseif guard.PropertyName == "Ancestors" then
		if typeof(guard.Value) ~= "table" then
			return invalidate("Ancestors property must be a table!" .. stackInfo)
		end
		if #guard.Value <= 0 then
			return invalidate("Ancestors property must have more than one element!" .. stackInfo)
		end

		local ancestors = Array.new("Instance", guard.Value)
		local matchedAncestor = ancestors:Some(function(ancestor)
			return ancestor:IsAncestorOf(instance)
		end)

		if not matchedAncestor then
			return invalidate(`Expected ancestors {ancestors} for instance {instance:GetFullName()}`)
		end
	elseif guard.PropertyName == "Attributes" then
		assert(typeof(guard.Value) == "table", "Attributes property must be a table!" .. stackInfo)
		for name, value in instance:GetAttributes() do
			local attributeGuard = guard.Value[name] :: Types.AttributeGuard?
			if attributeGuard then
				if typeof(value) ~= attributeGuard.Type then 
					return invalidate(`Expected "{name}" attribute's type to equal {value}, got {attributeGuard.Type}!{stackInfo}`)
				end

				if not attributeGuard.Value then continue end
				if attributeGuard.Value ~= value then
					return invalidate(`Expected "{name}" attribute's value to equal {value}, got {attributeGuard.Value}!{stackInfo}`)
				end
			end
		end
	elseif guard.PropertyName == "IsA" then
		if typeof(guard.Value) ~= "string" and typeof(guard.Value) ~= "Instance" then
			return invalidate("IsA property must be an Instance or a string!" .. stackInfo)
		end

		local message = `Expected instance {instance:GetFullName()} to be a sub-class of {guard.Value}, got {instance.ClassName}!{stackInfo}`
		if not instance:IsA(if typeof(guard.Value) == "Instance" then guard.Value.ClassName else guard.Value) then
			return invalidate(message)
		end
	else
		local hasProperty = pcall(function()
			return (instance :: any)[guard.PropertyName]
		end)
		if not hasProperty then
			return invalidate(`Instance "{instance:GetFullName()}" does not have property "{guard.PropertyName}".{stackInfo}`)
		end

		local propertyValue = (instance :: any)[guard.PropertyName]
		local guardIsComputed = typeof(guard.Value) == "function"
		if guardIsComputed then
			if not (guard.Value :: any)(propertyValue) then
				return invalidate(`Computed guard failed! Property name: "{guard.PropertyName}"{stackInfo}`)
			end
		else
			if guard.Value ~= propertyValue then
				return invalidate(`Expected value of instance property "{guard.PropertyName}" to equal {guard.Value}, got {(instance :: any)[guard.PropertyName]}!{stackInfo}`)
			end
		end
	end
	return
end

function validateGuards(componentName: string, instance: Instance, guards: Types.Guards, noErrorGuards: { string } | boolean): nil
	for propertyName, value in guards do
		local noError = if type(noErrorGuards) == "table" then Array.new("string", noErrorGuards or {}):Has(propertyName) else noErrorGuards
		validateGuard(componentName, instance, {
			PropertyName = propertyName,
			Value = value
		}, noError)
	end
	return
end

function Component:_ValidateDef(instance: Instance): nil
	local componentDef: Types.ComponentDef = self._def
	if not componentDef.Guards then return end
	validateGuards(componentDef.Name, instance, componentDef.Guards or {}, componentDef.NoErrorGuards or {})
	return
end

local function hasPrefix(name: string, prefix: string): boolean
	return name:sub(1, #prefix) == prefix
end

function Component:Add(instance: Instance): ComponentInstance.ComponentInstance?
	local ignored = false
	local componentDef: Def = self._def
	if componentDef.IgnoreAncestors then
		for _, ignoredAncestor in componentDef.IgnoreAncestors do
			if ignoredAncestor:IsAncestorOf(instance) then
				ignored = true
				break
			end
		end
	end

	if ignored then return end
	self:_ValidateDef(instance)
	local component = ComponentInstance.new(instance, componentDef)
	local eventPrefix = "Event_"
	local propertyChangePrefix = "PropertyChanged_"
	local attributeChangePrefix = "AttributeChanged_"

	for name: string, fn in pairs(componentDef) do
		if typeof(fn) ~= "function" then continue end

		task.spawn(function()
			local fn: (component: typeof(ComponentInstance)) -> () = fn
			local rightName = name:split("_")[2]
			if hasPrefix(name, eventPrefix) then
				component:AddToJanitor((instance :: any)[rightName]:Connect(function(...)
					(fn :: any)(component, ...)
				end))
			elseif hasPrefix(name, propertyChangePrefix) then
				component:AddToJanitor(instance:GetPropertyChangedSignal(rightName):Connect(function()
					fn(component)
				end))
			elseif hasPrefix(name, attributeChangePrefix) then
				component:AddToJanitor(instance:GetAttributeChangedSignal(rightName):Connect(function()
					fn(component)
				end))
			end
		end)
	end

	self.OwnedComponents:Push(component)
	return component :: ComponentInstance.ComponentInstance
end

function Component:Remove(instance: Instance, ignoreErrors: boolean?): nil
	ignoreErrors = ignoreErrors or false

	local component = (self :: any):Find(instance)
	if not ignoreErrors then
		assert(component ~= nil, `No {self._def.Name} components are attached to {instance:GetFullName()}`)
	end

	if component then
		_G.ComponentClasses:FindAndRemove(function(component: () -> Component): boolean
			return component().Name == self.Name
		end);
		(self.OwnedComponents :: any):RemoveValue(component)

		if not instance.Parent then return end
		component:Destroy()
	end
	return
end

return Component