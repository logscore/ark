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

	// sort installed array by installed time, newest first
	slice.sort_by(installed[:], proc(a, b: shared.Entry) -> bool {
		return a.timestamp > b.timestamp
	})

	// Resolve symlink version
	resolved_active_linked_file := shared.resolve_symlink_to_path(ark_dir, installed[0].binary)
	// path to the symlink itself, NOT the resolved target
	symlink_path, _ := os.join_path({ark_dir, "bin", installed[0].binary}, context.allocator)
	defer delete(symlink_path)

	package_git_repo_dir, _ := os.join_path(
		{ark_dir, "repo", strings.concatenate({package_name, ".git"})},
		context.allocator,
	)
	defer delete(package_git_repo_dir)

	// No version specified: uninstall everything
	if opts.version == "" {
		if resolved_active_linked_file != "" {
			_ = os.remove(symlink_path)
		}
		for entry in installed {
			versioned_build_dir, _ := os.join_path(
				{ark_dir, "build", package_name, entry.version},
				context.allocator,
			)
			os.remove_all(versioned_build_dir)
			delete(versioned_build_dir)
		}
		os.remove_all(package_git_repo_dir)

		// remove all package entries from the lock file
		remaining := make([dynamic]shared.Entry)
		defer delete(remaining)
		for entry in lock_data.data {
			if entry.name != package_name {
				append(&remaining, entry)
			}
		}
		if !shared.write_lock(ark_dir, remaining[:]) {
			fmt.println("ERROR: failed to write ark.lock")
			os.exit(1)
		}
		return
	}

	// Version specified: find that version. Capture value and remove from array
	found_entry: shared.Entry
	found_index := -1
	for entry, index in installed {
		if entry.version == opts.version {
			found_entry = entry
			found_index = index
			break
		}
	}
	if found_index == -1 {
		fmt.printfln("%s version %s is not installed", package_name, opts.version)
		os.exit(1)
	}
	unordered_remove(&installed, found_index)

	versioned_build_dir, _ := os.join_path(
		{ark_dir, "build", package_name, opts.version},
		context.allocator,
	)
	defer delete(versioned_build_dir)

	// remove the uninstalled version's entry from the lock file
	remaining := make([dynamic]shared.Entry)
	defer delete(remaining)
	for entry in lock_data.data {
		if entry.name == package_name && entry.version == found_entry.version {
			continue
		}
		append(&remaining, entry)
	}

	if len(installed) == 0 {
		// last version available
		fmt.printfln(
			"%[0]s is the last version available for %[1]s. After uninstall %[1]s wont be available.",
			opts.version,
			package_name,
		)
		if resolved_active_linked_file != "" {
			_ = os.remove(symlink_path)
		}
		os.remove_all(versioned_build_dir)
		os.remove_all(package_git_repo_dir)

		if !shared.write_lock(ark_dir, remaining[:]) {
			fmt.println("ERROR: failed to write ark.lock")
			os.exit(1)
		}
		return
	}

	// remaining >= 1
	// if requested version to uninstall is the same as the symlink version, relink
	if resolved_active_linked_file != "" {
		split_linked_path := strings.split(resolved_active_linked_file, "/")
		defer delete(split_linked_path)

		if len(split_linked_path) >= 2 &&
		   split_linked_path[len(split_linked_path) - 2] == opts.version {
			// TODO: Below is very temporary, we will give the user the navigable. This does undesired behavior that needs documentation to understand and i dont like that.
			// select screen to pick the version they want to be active after uninstall
			replacement_index :=
				found_index + 1 < len(installed) ? found_index + 1 : found_index - 1

			// index will always be >= 0
			replacement := installed[replacement_index]

			new_binary_to_link, _ := os.join_path(
				{ark_dir, "build", package_name, replacement.version, replacement.binary},
				context.allocator,
			)
			defer delete(new_binary_to_link)

			_ = os.remove(symlink_path)
			if err := os.symlink(new_binary_to_link, symlink_path); err != nil {
				fmt.printfln("ERROR: failed to relink %s: %v", replacement.binary, err)
			}
		}
	}

	os.remove_all(versioned_build_dir)

	if !shared.write_lock(ark_dir, remaining[:]) {
		fmt.println("ERROR: failed to write ark.lock")
		os.exit(1)
	}
}
