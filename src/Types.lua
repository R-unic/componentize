--!native
--!strict
export type ComponentOptions = {
	UseTags: boolean?
}

export type AttributeValue =
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
	| Font

export type AttributeType =
	"string"
	| "boolean"
	| "number"
	| "Vector2"
	| "Vector3"
	| "CFrame"
	| "Rect"
	| "Font"
	| "BrickColor"
	| "Color"
	| "UDim"
	| "UDim2"
	| "NumberSequence"
	| "ColorSequence"
	| "NumberRange"

export type AttributeGuard = {
	Type: AttributeType;
	Value: AttributeValue?;
}

export type Guards = {
	[string]: any;
	IsA: string?;
	Attributes: { [string]: AttributeGuard }?;
	Ancestors: { Instance }?;
	Children: Guards?;
}

export type ComponentDef = {
	Name: string;
	LoadOrder: number?;
	IgnoreAncestors: { Instance }?;
	Guards: Guards?;
	[string]: any;
}

return {}