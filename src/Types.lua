--!native
--!strict
export type ComponentOptions = {
	UseTags: boolean?
}

export type ComponentDef = {
	Name: string;
	Guards: { [string]: any } ?;
	Ancestors: { Instance }?;
	[string]: any;
}

return {}