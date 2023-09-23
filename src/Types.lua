--!native
--!strict
export type ComponentOptions = {
	UseTags: boolean?
}

export type ComponentDef = {
	Name: string;
	Guards: { [string]: any } ?;
	IgnoreAncestors: { Instance }?;
	Ancestors: { Instance }?;
	[string]: any;
}

return {}