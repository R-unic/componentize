--!native
--!strict
local CollectionService = game:GetService("CollectionService")

local ComponentInstance = require(script.ComponentInstance)
local Array = require(script.Parent.Array)
local Types = require(script.Types)

_G.ComponentClasses = _G.ComponentClasses or Array.new()
local Component = {}
Component.__index = Component

export type Def = Types.ComponentDef
export type Component = typeof(Component) & {
	Name: string;
	OwnedComponents: typeof(Array);
}

type InstanceGuard<T> = {
	PropertyName: string;
	Value: T;
}

function Component.Get(name: string): Component
	local component = _G.ComponentClasses
		:Find(function(component)
			return component.Name == name
		end)

	assert(component ~= nil, `Failed to get component: Component "{name}" does not exist!`)
	return component
end

function Component.Load(module: ModuleScript): nil
	_G.ComponentClasses:Push(require(module) :: any)
	return
end

function Component.LoadFolder(folder: Folder): nil
	for _, module: Instance in folder:GetDescendants() do
		if module:IsA("ModuleScript") then
			task.spawn(function()
				Component.Load(module)
			end)
		end
	end
	return
end

function Component.StartComponents(): nil
	for component: Component in _G.ComponentClasses:Values() do
		task.spawn(function()
			component:_Start()
		end)
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
	self._def = def

	self._useTags = true
	if options and options.UseTags ~= nil then
		self._useTags = options.UseTags
	end

	return self
end

function Component:_Start(): nil
	if self._useTags then
		CollectionService:GetInstanceAddedSignal(self._def.Name):Connect(function(instance: Instance)
			self:Add(instance)
		end)
		CollectionService:GetInstanceRemovedSignal(self._def.Name):Connect(function(instance: Instance)
			self:Remove(instance, true)
		end)

		Array.new("Instance", CollectionService:GetTagged(self._def.Name))
			:ForEach(function(instance: Instance)
				task.spawn(function()
					self:Add(instance)
				end)
			end)
	end
	return
end

function Component:Find(instance: Instance): ComponentInstance.ComponentInstance?
	return self.OwnedComponents:Find(function(component: ComponentInstance.ComponentInstance)
		return component.Instance == instance
	end)
end

local validateGuards = nil
local function validateGuard<T>(componentName: string, instance: Instance, guard: InstanceGuard<T>): nil
	local stackInfo = ` ({componentName} :> {instance:GetFullName()})`
	if guard.PropertyName == "Children" then
		for childName, childGuards: Types.Guards in guard.Value :: any do
			local child = instance:WaitForChild(childName, 7)
			assert(child ~= nil, `Child "{childName}" does not exist on {instance:GetFullName()}!` .. stackInfo)
			validateGuards(componentName, child, childGuards)
		end
	elseif guard.PropertyName == "Ancestors" then
		assert(typeof(guard.Value) == "table", "Ancestors property must be a table!" .. stackInfo)
		assert(#guard.Value > 0, "Ancestors property must have more than one element!" .. stackInfo)

		local ancestors = Array.new("Instance", guard.Value)
		assert(ancestors:Some(function(ancestor)
			return ancestor:IsAncestorOf(instance)
		end), `Expected ancestors {ancestors} for instance {instance:GetFullName()}`)
	elseif guard.PropertyName == "Attributes" then
		assert(typeof(guard.Value) == "table", "Attributes property must be a table!" .. stackInfo)
		for name, value in instance:GetAttributes() do
			local attributeGuard = guard.Value[name] :: Types.AttributeGuard?
			if attributeGuard then
				assert(attributeGuard.Type == typeof(value), `Expected "{name}" attribute's type to equal {value}, got {attributeGuard.Type}!` .. stackInfo)
				if not attributeGuard.Value then continue end
				assert(attributeGuard.Value == value, `Expected "{name}" attribute's value to equal {value}, got {attributeGuard.Value}!` .. stackInfo)
			end
		end
	elseif guard.PropertyName == "IsA" then
		assert(typeof(guard.Value) == "string" or typeof(guard.Value) == "Instance", "IsA property must be an Instance or a string!" .. stackInfo)

		local message = `Expected instance {instance:GetFullName()} to be a sub-class of {guard.Value}, got {instance.ClassName}!` .. stackInfo
		if typeof(guard.Value) == "Instance" then
			assert(instance:IsA(guard.Value.ClassName), message)
		else
			assert(instance:IsA(guard.Value), message)
		end
	else
		local hasProperty = pcall(function()
			return (instance :: any)[guard.PropertyName]
		end)
		assert(hasProperty, `Instance "{instance:GetFullName()}" does not have property "{guard.PropertyName}".` .. stackInfo)

		local propertyValue = (instance :: any)[guard.PropertyName]
		local guardIsComputed = typeof(guard.Value) == "function"
		if guardIsComputed then
			assert((guard.Value :: any)(propertyValue), `Computed guard failed! Property name: "{guard.PropertyName}"` .. stackInfo)
		else
			assert(guard.Value == propertyValue, `Expected value of instance property "{guard.PropertyName}" to equal {guard.Value}, got {(instance :: any)[guard.PropertyName]}!` .. stackInfo)
		end
	end
	return
end

function validateGuards(componentName: string, instance: Instance, guards: Types.Guards): nil
	for propertyName, value in guards do
		task.spawn(function()
			validateGuard(componentName, instance, {
				PropertyName = propertyName,
				Value = value
			})
		end)
	end
	return
end

function Component:_ValidateDef(instance: Instance): nil
	local componentDef: Types.ComponentDef = self._def
	if not componentDef.Guards then return end
	validateGuards(componentDef.Name, instance, componentDef.Guards)
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
	if ignoreErrors == nil then
		ignoreErrors = false
	end

	local component = (self :: any):Find(instance)
	if not ignoreErrors then
		assert(component ~= nil, `No {self._def.Name} components are attached to {instance:GetFullName()}`)
	end

	if component then
		(self.OwnedComponents :: any):RemoveValue(component)
		component:Destroy()
	end
	return
end

return Component