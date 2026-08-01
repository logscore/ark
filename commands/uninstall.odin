package commands

import help "../help"
import shared "../shared"

import "core:flags"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

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
	found_index: int
	if opts.version != "" {
		found := false
		for entry, index in installed {
			if entry.version == opts.version {
				found_entry = entry
				found_index = index
				// Remove the desired version from the array here.
				ordered_remove(&installed, index)
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
			// delete the symlink. We dont need to handle errors here as we know the symlink exists and ark clean can clean the orphaned file
			_ = os.remove_all(resolved_active_linked_file)
		}

		// delete the ~/.ark/build/<package_name>/<version>
		versioned_build_dir, _ := os.join_path(
			{ark_dir, "build", package_name, opts.version},
			context.allocator,
		)
		os.remove(versioned_build_dir)
		delete(versioned_build_dir)

		// delete ~/.ark/repo/<package_name>.git
		package_git_repo_dir, _ := os.join_path(
			{ark_dir, "repo", strings.concatenate({package_name, ".git"})},
			context.allocator,
		)
		os.remove(package_git_repo_dir)
		delete(package_git_repo_dir)

		// remove the package entries data from the lock file
		for entry, index in lock_data.data {
			if entry.name == package_name && entry.version == found_entry.version {
				ordered_remove(&lock_data.data, index)
			}
		}

		// Write to lock file
		if !shared.write_lock(ark_dir, lock_data.data[:]) {
			fmt.println("ERROR: failed to write ark.lock")
			os.exit(1)
		}
	} else if len(installed) >= 1 {
		// If there are more than one package of that name...

		//
		split_linked_path := strings.split(resolved_active_linked_file, "/")
		// if requested version to uninstall is the same as the symlink version
		if split_linked_path[len(split_linked_path) - 2] == opts.version {
			// TODO: Below is very temporary, we will give the user the navigable select screen to pick the version they want to be active after uninstal
			// set the symlinked version as the most recent version.
			new_binary_to_link, _ := os.join_path(
				{
					ark_dir,
					"build",
					package_name,
					installed[found_index + 1].version,
					installed[found_index + 1].binary,
				},
			)
			new_symlink_path, _ := os.join_path(
				{ark_dir, "bin", installed[found_index + 1].binary},
				context.allocator,
			)

			_ = os.symlink(new_binary_to_link, new_symlink_path)

			delete(new_binary_to_link)
			delete(new_symlink_path)
		}
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
