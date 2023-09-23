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

type Guards = {
	[string]: any;
	IsA: string;
	Attributes: { [string]: AttributeValue };
	Ancestors: { Instance }?;
	Children: Guards;
}

export type ComponentDef = {
	Name: string;
	IgnoreAncestors: { Instance }?;
	Guards: Guards?;
}

return {}