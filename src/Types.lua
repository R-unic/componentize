--!native
--!strict
export type ComponentOptions = {
	UseTags: boolean?
}

export type ComponentDef = {
	Name: string;
	ClassName: string?;
	Ancestors: { Instance }?;
	[string]: any;
}

return {}