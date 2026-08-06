package shared

import "core:fmt"

Help :: struct {
	name: string,
	text: string,
}

HELP :: [?]Help {
	{
		"install",
		`Usage: ark install <repo_url> [--version <version>] [--force]

Clone, build, and install a package from a Git repository.

Arguments:
  <repo_url>       Repository URL. The url can be https:// or git@

Options:
  --version        Install a specific version instead of the latest.
  				   Version may be a tag, branch, or commit sha
                   The version may be older than the installed version.
  --force          Skip the hash check and reinstall the tool

`,
	},
	{
		"uninstall",
		`Usage: ark uninstall <package_name> [--version <version>]

Uninstall a tool. Does not uninstall data created by the tool.

Arguments:
  <package_name>	   Package name to uninstall.
  					   Without a --version, removes all installed versions.

Options:
  --version <version>  Uninstall a specific version instead of the active version.
  					   Version can be a tag, branch, or commit sha.
`,
	},
	{
		"update",
		`Usage: ark update <package_name> [--version <version>] [--force]

Update a tool to the latest available version.

Arguments:
  <package_name>       Package to update.

Options:
  --version <version>  Install a specific version instead of the latest.
                       The version may be older than the installed version.
  --force              Reinstall even if the requested version is installed.
`,
	},
	{
		"list",
		`Usage: ark list <package_name> [--version <version>]

List installed tools.

Arguments:
  <package_name>       Optionally filter by tool name and version.

Options:
  --version <version>  List a specific version of the specified package.
`,
	},
	{
		"use",
		`Usage: ark use <package_name> <version>

Set the active version of a tool.

Updates the symlink in ~/.ark/bin. No rebuild is required, so switching versions is immediate.

Arguments:
  <package_name>	Package to activate
  <version>             Version of the specified package to activate
`,
	},
	{
		"build",
		`Usage: ark build <path> [--with <cmd>] [--no-cache-tools]

Detect the project toolchain and run its build script.
Detection supports: Go, Rust, Zig, Make, Typescript (via Bun), C/C++ (via Zig) and Odin.

Arguments:
  <path>            Path to the project.

Options:
  --with <cmd>      Override toolchain detection and run this command.
  --no-cache-tools  Store tools in .ark/tools and remove them after the build.
                    Intended for CI environments.
`,
	},
}

default_help :: `ark - Git-based package manager

Usage:
  ark <command> [arguments] [options]

Commands:
  install <repo_url> [--version <version>] [--force]
    Clone, build, and install a package from a Git repository.
    --version <version>  Install a tag, branch, or commit SHA.
    --force              Skip the hash check and reinstall the package.

  uninstall <package_name> [--version <version>]
    Uninstall a package. Does not remove data created by the package.
    --version <version>  Uninstall a specific version.
                         Without --version, removes all installed versions.

  update <package_name> [--version <version>] [--force]
    Update a package to the latest available version.
    --version <version>  Install a specific version instead of the latest.
    --force              Reinstall even if the requested version is installed.

  list <package_name> [--version <version>]
    List installed versions of a package.
    --version <version>  List a specific installed version.

  use <package_name> <version>
    Set the active version of a package.
    Updates the symlink in ~/.ark/bin. No rebuild is required.

  build <path> [--with <cmd>] [--no-cache-tools]
    Detect the project toolchain and run its build script.
    Supports Go, Rust, Zig, Make, TypeScript via Bun, C/C++ via Zig, and Odin.
    --with <cmd>          Override toolchain detection and run this command.
    --no-cache-tools      Store tools in .ark/tools and remove them after
                          the build. Intended for CI environments.

Run "ark <command> --help" for command-specific help.
`

print_help :: proc(command: string) {
	for h in HELP {
		if h.name == command {
			fmt.println(h.text)
			return
		}
	}
	fmt.println(default_help)
}

/*
   __        ark - git package manager
  /  \       Usage: ark <command> [args] [options]
 / /\ \
/ /__\ \     Commands:
               install <repo> [-v <ver>] [-f]   clone, build, install
               uninstall <pkg> [-v <ver>]       remove package/data stays
               update <pkg> [-v <ver>] [-f]     update to latest
               list [pkg] [-v <ver>]            list installed versions
               use <pkg> <ver>                  set active version in ~/.ark/bin
               build [path] [--with cmd]        build via detected toolchain

               Run `ark <cmd> --help` for details.
*/
