package commands

import "core:flags"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"

import git "../git"
import help "../help"
import shared "../shared"

Install_Options :: struct {
	version: string `args: "name=version" `,
	force:   bool `args: "name=force"`,
}

install_package :: proc(home_dir: string, options: []string) {
	if len(options) < 1 {
		fmt.println("Invalid usage:\n")
		help.print_help("install")
		os.exit(1)
	}

	arg_flags := options[1:]
	opts: Install_Options
	if len(arg_flags) != 0 {
		flags.parse(&opts, arg_flags, .Unix)
	}

	url := options[0]

	if url == "--help" {
		help.print_help("install")
		os.exit(0)
	}

	repo_data := shared.Repo {
		url  = "",
		name = "",
		spec = "",
	}

	if opts.version == "" {
		repo_data.spec = "HEAD"
	} else {
		repo_data.spec = opts.version
	}

	// parse url.
	// TODO: eventually support bare github.com/user/tool or user/tool
	scheme, host, full_path, _, _ := net.split_url(url)

	fmt.println(host, full_path)

	if scheme == "" && strings.starts_with(host, "git@") {
		repo_data.url = strings.concatenate({host, strings.split(full_path, "@")[0]})
	} else if scheme == "https" {
		repo_data.url = strings.concatenate({scheme, "://", host})
	} else {
		fmt.printfln("Invalid repo url: %s\n", url)
		help.print_help("install")
		os.exit(1)
	}

	fmt.println(repo_data.url)

	base := strings.split(full_path, "@")[0]
	base = strings.trim_suffix(base, ".git")
	path_tokens := strings.split(base, "/")
	repo_data.name = path_tokens[len(path_tokens) - 1]

	lock_data, lock_ok := shared.read_lock(home_dir)
	if !lock_ok {
		fmt.println("ERROR: failed to read ark.lock file")
		os.exit(1)
	}

	// Process out to git, clone to .ark/cache
	tmp_build_dir := git.resolve_repo(home_dir, "install", repo_data, lock_data, opts.force)

	// run builder
	fmt.println("Running builder")
	// run installer
	fmt.println("Running installer")
	// run lock updater
	fmt.println("Updating lock")

}
