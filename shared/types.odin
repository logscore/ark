package shared


Repo :: struct {
	url:  string,
	name: string,
	spec: string, // this is the tag, HEAD, or sha
}

Entry :: struct {
	name:      string,
	version:   string,
	sha:       string,
	repo:      string,
	binary:    string,
	timestamp: i64,
}

Lock_Data :: struct {
	data: [dynamic]Entry,
}

Build :: struct {
	build_tool: string `json:"build_tool"`,
	version:    string `json:"version"`,
	args:       []string `json:"args"`,
	env:        map[string]string `json:"env"`,
}

Package :: struct {
	name:  string `json:"name"`,
	build: Build `json:"build"`,
	out:   string `json:"out"`,
}

User_Config :: struct {
	packages: []Package `json:"tools"`,
}
