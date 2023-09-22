--!native
--!strict
local CollectionService = game:GetService("CollectionService")

local ComponentInstance = require(script.ComponentInstance)
local Array = require(script.Parent.array)
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

local function validateComponentDef(componentDef: Types.ComponentDef, instance: Instance): nil
	if componentDef.ClassName ~= nil then
		assert(typeof(componentDef.ClassName) == "string", "ClassName property must be a string!")
		assert(componentDef.ClassName == instance.ClassName, `Expected instance to be of type {componentDef.ClassName}, got {instance.ClassName}!`)
	end
	if componentDef.Ancestors ~= nil then
		assert(typeof(componentDef.Ancestors) == "table", "Ancestors property must be a table!")
		assert(#componentDef.Ancestors > 0, "Ancestors property must have more than one element!")

		local ancestors = Array.new(componentDef.Ancestors)
		assert(ancestors:Every(function(ancestor)
			return typeof(ancestor) == "Instance"
		end), "Ancestors table property must only contain instances!")
		
		assert(ancestors:Some(function(ancestor)
			return ancestor:IsAncestorOf(instance)
		end), `Expected ancestors {ancestors:ToTable()} for instance {instance:GetFullName()}`)
	end
	return
end

function Component:Add(instance: Instance): ComponentInstance.ComponentInstance
	local componentDef = self._def
	validateComponentDef(componentDef, instance)
	
	local component = ComponentInstance.new(instance, componentDef)
	local prefix = "Event_"
	for name: string, fn in componentDef do
		if typeof(fn) ~= "function" then continue end
		if name:sub(1, #prefix) == prefix then
			local eventName = name:split(prefix)[2]
			component:AddToJanitor((instance :: any)[eventName]:Connect(function(...)
				(fn :: any)(component, ...)
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