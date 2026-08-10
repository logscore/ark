package shared


REF_KIND_TAG :: "tag"
REF_KIND_BRANCH :: "branch"
REF_KIND_COMMIT :: "commit"
REF_KIND_DEFAULT :: "default"
REF_KIND_LEGACY :: "legacy"

Repo :: struct {
	url:         string,
	name:        string,
	spec:        string,
	default_ref: bool,
}

Entry :: struct {
	name:      string,
	version:   string,
	sha:       string,
	url:       string,
	binary:    string,
	timestamp: i64,
	ref_kind:  string,
	ref_name:  string,
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
