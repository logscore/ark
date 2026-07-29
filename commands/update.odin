package commands

import git "../git"
import help "../help"
import shared "../shared"

import "core:flags"
import "core:fmt"
import "core:os"
import "core:path/filepath"

Update_Options :: struct {
	force:   bool `args: "name=force"`,
	version: string `args: "name=version"`,
}

update_package :: proc(home_dir: string, options: []string) {
	if len(options) < 1 {
		fmt.println("Invalid usage:\n")
		help.print_help("update")
		os.exit(1)
	}

	package_name := options[0]
	arg_flags := options[1:]

	opts: Update_Options
	if len(arg_flags) != 0 {
		flags.parse(&opts, arg_flags, .Unix)
	}

	if package_name == "--help" {
		help.print_help("update")
		os.exit(0)
	}
	lock_data, lock_ok := shared.read_lock(home_dir)
	if !lock_ok {
		fmt.println("ERROR: failed to read ark.lock file")
		os.exit(1)
	}
	defer delete(lock_data.data)

	// filter lock data to only the name of the package requested
	installed := make([dynamic]shared.Entry)
	for line in lock_data.data {
		if line.name == package_name {
			append(&installed, line)
		}
	}

	if len(installed) == 0 {
		fmt.printfln(`%s not installed, use 'ark install'`, package_name)

		os.exit(1)
	}

	want_version := opts.version
	if want_version == "" {
		want_version = "HEAD" // or resolve HEAD from remote
	}

	// get active version symlink location.
	active_version := shared.resolve_binary_version(home_dir, installed[0].binary)
	if active_version == "" {
		fmt.printfln(
			"Package '%s' has no available binary.\n\nPlease run 'ark install %s' to install the package",
			package_name,
			installed[0].repo,
		)
		os.exit(1)
	}
	// NOTE: We should run into an instance where we have two tools of the same name from different publishers. Well do that eventually, but install will block adding packages of the same name
	// // 3. disambiguate same name different repo
	// target_entry := installed[0]
	// if len(installed) > 1 {
	//     // if repos differ, prompt user to pick
	//     // target_entry = prompt_pick_repo(installed) // up/down UI
	//     fmt.println("More than one tool of this name, which do we update?", installed)
	// }

	repo_data: shared.Repo

	// if already on disk, just flip symlink
	for e in installed {
		if e.version == want_version {
			fmt.printfln(
				"Version %s already installed, switching active package to %s",
				want_version,
			)
			store_path, store_err := filepath.join(
				{home_dir, ".ark", "builds", e.name, e.version, e.binary},
			)
			if store_err != nil {
				fmt.println("Failed to build binary store directory.")
				os.exit(1)
			}
			bin_path, bin_err := filepath.join({home_dir, ".ark", "bin", e.binary})
			if bin_err != nil {
				fmt.println("Failed to build binary link directory.")
				os.exit(1)
			}
			rel, _ := filepath.rel(filepath.dir(bin_path), store_path, context.temp_allocator)
			os.remove(bin_path)
			os.symlink(rel, bin_path) // target, link
			return
		} else if e.version == active_version {
			repo_data.url = e.repo
			repo_data.name = e.name
			repo_data.spec = want_version
		}
	}
	delete(installed)

	// pull desired version
	tmp_build_dir := git.resolve_repo(home_dir, "update", repo_data, lock_data, opts.force)

	// run builder
	fmt.println("Running builder")
	// run installer
	fmt.println("Running installer")
	// run lock updater
	fmt.println("Updating lock")
}
