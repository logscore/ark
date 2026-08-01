package commands

import help "../help"
import shared "../shared"

import "core:flags"
import "core:fmt"
import "core:os"
import "core:slice"

Uninstall_Options :: struct {
	version: string `args: "name=version"`,
}

uninstall_package :: proc(ark_dir: string, options: []string) {
	// validate inputs
	if len(options) < 1 {
		fmt.println("Invalid usage:\n")
		help.print_help("uninstall")
		os.exit(1)
	}

	package_name := options[0]
	arg_flags := options[1:]

	if package_name == "--help" {
		help.print_help("uninstall")
		os.exit(0)
	}

	// TODO: FOR ALL. we need to parse the options and give valid errors saying "Unrecognized flag" if the user passes an unsupported flag
	opts: Uninstall_Options
	if len(arg_flags) != 0 {
		flags.parse(&opts, arg_flags, .Unix)
	}

	lock_data, lock_ok := shared.read_lock(ark_dir)
	if !lock_ok {
		fmt.println("ERROR: failed to read ark.lock file")
		os.exit(1)
	}
	defer delete(lock_data.data)

	// filter lock data to only the name of the package requested
	installed := make([dynamic]shared.Entry)
	defer delete(installed)
	for line in lock_data.data {
		if line.name == package_name {
			append(&installed, line)
		}
	}

	if len(installed) == 0 {
		fmt.printfln(`%s not installed`, package_name)

		// TODO: uncomment when clean is implemented
		// build_dir := filepath.join({home_dir, ".ark", "build", package_name})
		// repo_dir := filepath.join({home_dir, ".ark", "repo", package_name + ".git"})

		// if os.exists(build_dir) || os.exists(repo_dir) {
		// 	fmt.println("stale files found, run 'ark clean' to remove them")
		// }

		os.exit(1)
	}

	// If the user specified a version, find that version. Capture value and remove from array
	found_entry: shared.Entry
	if opts.version != "" {
		found := false
		for entry, index in installed {
			if entry.version == opts.version {
				found_entry = entry
				// Remove the desired version from the array here.
				unordered_remove(&installed, index)
				found = true
				break
			}
		}
		if !found {
			fmt.printfln("%s %s is not installed", package_name, opts.version)
			os.exit(1)
		}
	}

	// Resolve symlink version
	resolved_active_linked_file := shared.resolve_symlink_to_path(ark_dir, found_entry.binary)
	// sort installed array by installed time
	slice.sort_by(installed[:], proc(a, b: shared.Entry) -> bool {
		return a.timestamp > b.timestamp
	})
	// 	If remaining array == 0
	if len(installed) == 0 {
		// Tell them "this is the last version available. After uninstall 'package_name' wont be available."
		fmt.printfln(
			"%[0]s is the last version available for %[1]s. %[1]s wont be available for the user.",
			opts.version,
			package_name,
		)
		// if symlink version != ""
		if resolved_active_linked_file != "" {
			// delete the symlink
			os.remove(resolved_active_linked_file)
		}
		// 		delete the ~/.ark/build/<package_name>/<version>
		// 		delete ~/.ark/repo/<package_name>.git
		// 		remove the package entries data from the lock file
		// 	If remaining array >= 1
		// 		if requested version to uninstall is the same as the symlink version
		// 			TODO: Below is very temporary, we will give the user the navigable select screen to pick the version they want to be active after uninstal
		// 			set the symlinked version as the most recent version.
		// 		delete ~/.ark/build/<package_name>/<version>
		// 		remove the package entry data from the lock file
		// else
	} else {
		// 	if symlink version != ""
		// 		delete the symlink
		// 	for x in installed array
		// 		delete the ~/.ark/build/<package_name>/<version>
		// 	delete ~/.ark/repo/<package_name>.git
		// 	remove the package entries data from the lock file
	}
}
