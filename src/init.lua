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

function Component.Get(name: string): typeof(Component)?
	return _G.ComponentClasses
		:Find(function(component)
			return component.Name == name
		end)
end

function Component.Load(module: ModuleScript): nil
	_G.ComponentClasses:Push(require(module) :: any)
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
	for component: typeof(Component) & { Name: string } in _G.ComponentClasses:Values() do
		component:_Start()
	end
	return
end

function Component.new(def: Types.ComponentDef, options: Types.ComponentOptions?)
	assert(def ~= nil, "Must provide a component definition.")
	assert(def.Name ~= nil, "Must provide Name property!")
	assert(typeof(def.Name) == "string", "Component name must be a string!")
	assert(#def.Name > 0, "Component name must have at least one character!")

	local self = setmetatable({}, Component)
	self.Name = def.Name
	self._def = def
	self._ownedComponents = Array.new("table")

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
			self:Remove(instance)
		end)

		Array.new("Instance", CollectionService:GetTagged(self._def.Name))
			:ForEach(function(instance: Instance)
				self:Add(instance)
			end)
	end
end

function Component:Find(instance: Instance): ComponentInstance.ComponentInstance?
	return self._ownedComponents:Find(function(component: ComponentInstance.ComponentInstance)
		return component.Instance == instance
	end)
end

type InstanceGuard<T> = {
	PropertyName: string;
	Value: T;
}

local validateGuards
local function validateGuard<T>(instance: Instance, guard: InstanceGuard<T>): nil
	if guard.PropertyName == "Children" then
		for childName, childGuards: InstanceGuard<any> in guard.Value :: any do
			local child = instance:FindFirstChild(childName)
			assert(child ~= nil, `Child "{childName}" does not exist on {instance:GetFullName()}!`)
			validateGuards(child, childGuards)
		end
	elseif guard.PropertyName == "Ancestors" then
		assert(typeof(guard.Value) == "table", "Ancestors property must be a table!")
		assert(#guard.Value > 0, "Ancestors property must have more than one element!")

		local ancestors = Array.new("Instance", guard.Value)
		assert(ancestors:Some(function(ancestor)
			return ancestor:IsAncestorOf(instance)
		end), `Expected ancestors {ancestors} for instance {instance:GetFullName()}`)
	elseif guard.PropertyName == "IsA" then
		assert(typeof(guard.Value) == "string" or typeof(guard.Value) == "Instance", "IsA property must be an Instance or a string!")
		
		local message = `Expected instance {instance:GetFullName()} to be a sub-class of {guard.Value}, got {instance.ClassName}!`
		if typeof(guard.Value) == "Instance" then
			assert(instance:IsA(guard.Value.ClassName), message)
		else
			assert(instance:IsA(guard.Value), message)
		end
	else
		local hasProperty = pcall(function()
			return (instance :: any)[guard.PropertyName]
		end)

		assert(hasProperty, `Instance "{instance:GetFullName()}" does not have property "{guard.PropertyName}".`)
		assert(guard.Value == (instance :: any)[guard.PropertyName], `Expected value of instance property "{guard.PropertyName}" to equal {guard.Value}, got {(instance :: any)[guard.PropertyName]}!`)
	end
	return
end

function validateGuards(instance: Instance, guards: { [string]: any }): nil
	for propertyName, value in guards do
		validateGuard(instance, {
			PropertyName = propertyName,
			Value = value
		})
	end
end

function Component:_ValidateDef(instance: Instance): nil
	local componentDef: Types.ComponentDef = self._def
	if not componentDef.Guards then return end
	validateGuards(instance, componentDef.Guards)
	return
end

local function hasPrefix(name: string, prefix: string): boolean
	return name:sub(1, #prefix) == prefix
end

function Component:Add(instance: Instance): ComponentInstance.ComponentInstance
	self:_ValidateDef(instance)

	local componentDef = self._def
	local component = ComponentInstance.new(instance, componentDef)
	local eventPrefix = "Event_"
	local propertyChangePrefix = "PropertyChanged_"
	local attributeChangePrefix = "AttributeChanged_"

	for name: string, fn in componentDef do
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

	self._ownedComponents:Push(component)
	return component :: ComponentInstance.ComponentInstance
end

function Component:Remove(instance: Instance): nil
	local component = (self :: any):Find(instance)
	assert(component ~= nil, `No {self._def.Name} components are attached to {instance:GetFullName()}`);

	(self._ownedComponents :: any):RemoveValue(component)
	component:Destroy()
	return
end

return Component