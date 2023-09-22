--!native
--!strict
local CollectionService = game:GetService("CollectionService")

local ComponentInstance = require(script.ComponentInstance)
local Array = require(script.Parent.Array)
local Types = require(script.Types)

local ComponentClasses = {}
local Component = {}
Component.__index = Component

export type Def = Types.ComponentDef

function Component.Load(module: ModuleScript): nil
	table.insert(ComponentClasses, require(module) :: any)
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

function Component.new(def: Types.ComponentDef, options: Types.ComponentOptions?)
	assert(def ~= nil, "Must provide a component definition.")
	assert(def.Name ~= nil, "Must provide Name property!")
	assert(typeof(def.Name) == "string", "Component name must be a string!")
	assert(#def.Name > 0, "Component name must have at least one character!")
	
	local self = setmetatable({}, Component)
	self._def = def
	self._ownedComponents = Array.new()
	
	local useTags = true
	if options and options.UseTags ~= nil then
		useTags = options.UseTags
	end
	
	if useTags then
		CollectionService:GetInstanceAddedSignal(def.Name):Connect(function(instance: Instance)
			self:Add(instance)
		end)
		CollectionService:GetInstanceRemovedSignal(def.Name):Connect(function(instance: Instance)
			self:Remove(instance)
		end)
		Array.new(CollectionService:GetTagged(def.Name))
			:ForEach(function(instance: Instance)
				self:Add(instance)
			end)
	end
	
	return self
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

function Component:_ValidateDef(instance: Instance): nil
	local componentDef: Types.ComponentDef = self._def
	if componentDef.Guards ~= nil then
		local function validateGuard<T>(i: Instance, guard: InstanceGuard<T>): nil
			if guard.PropertyName == "Children" then
				for childName, child: InstanceGuard<any> in guard.Value :: any do
					validateGuard(i:FindFirstChild(childName) :: Instance, child)
				end
			elseif guard.PropertyName == "Ancestors" then
				assert(typeof(guard.Value) == "table", "Ancestors property must be a table!")
				assert(#guard.Value > 0, "Ancestors property must have more than one element!")

				local ancestors = Array.new(guard.Value)
				assert(ancestors:Every(function(ancestor)
					return typeof(ancestor) == "Instance"
				end), "Ancestors table property must only contain instances!")
				
				assert(ancestors:Some(function(ancestor)
					return ancestor:IsAncestorOf(instance)
				end), `Expected ancestors {ancestors:ToTable()} for instance {instance:GetFullName()}`)
			else
				local hasProperty = pcall(function()
					return (instance :: any)[guard.PropertyName]
				end)
	
				assert(hasProperty, `Instance "{instance:GetFullName()} does not have property "{guard.PropertyName}".`)
				assert(guard.Value == (instance :: any)[guard.PropertyName], `Expected value of instance property "{guard.PropertyName}" to equal {componentDef[guard.PropertyName]}, got {(instance :: any)[guard.PropertyName]}!`)
			end
			return
		end

		for propertyName, value in componentDef.Guards do
			validateGuard(instance, {
				PropertyName = propertyName,
				Value = value
			})
		end
	end
end

function Component:Add(instance: Instance): ComponentInstance.ComponentInstance
	self:_ValidateDef(instance)
	
	local componentDef = self._def
	local component = ComponentInstance.new(instance, componentDef)
	local eventPrefix = "Event_"
	local propertyChangePrefix = "PropertyChanged_"
	local function hasPrefix(name: string, prefix: string): boolean
		return name:sub(1, #prefix) == prefix
	end

	for name: string, fn in componentDef do
		if typeof(fn) ~= "function" then continue end
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
		end
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