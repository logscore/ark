package commands

import "core:flags"
import "core:fmt"
import "core:os"
import "core:strings"

import shared "../shared"

Use_Options :: struct {
	package_name: string `args:"name=package_name,pos=0,required"`,
	version:      string `args:"name=version,pos=1,required"`,
}

// TODO: Eventually we will add --global (default), --local, and --shell
use_package :: proc(ark_dir: string, options: []string) {
	opts: Use_Options
	err := flags.parse(&opts, options, .Unix)
	switch v in err {
	case flags.Help_Request:
		shared.print_help("use")
		os.exit(0)
	case flags.Parse_Error:
		fmt.println(v.message)
		os.exit(1)
	case flags.Open_File_Error:
		fmt.println("Could not open", v.filename)
		os.exit(1)
	case flags.Validation_Error:
		fmt.println(v.message)
		os.exit(1)
	}

	// Check that the package exists.
	lock_data, lock_ok := shared.read_lock(ark_dir)
	if !lock_ok {
		os.exit(1)
	}

	installed: shared.Entry
	found: bool
	for line in lock_data.data {
		if line.name == opts.package_name && line.version == opts.version {
			installed = line
			found = true
			break
		}
	}

	if !found {
		fmt.printfln(
			"Package %[0]s of version '%[1]s' is not installed. To install, run:\n\n    ark install <repo_url> --version %[1]s\n\n",
			opts.package_name,
			opts.version,
		)
		os.exit(1)
	}

	// Check that the current active version isnt the version requested
	current_active_version_path := shared.resolve_symlink_to_path(ark_dir, installed.binary)

	if current_active_version_path != "" {
		split_linked_path := strings.split(current_active_version_path, "/")
		defer delete(split_linked_path)

		// check that the current linked version is different from the requested version
		active_version := split_linked_path[len(split_linked_path) - 2]
		if active_version == opts.version {
			fmt.printfln(
				"%[0]s of version %[1]s is already active.",
				opts.package_name,
				opts.version,
			)
		}
	}
	new_binary_file_to_link, new_build_dir_err := os.join_path(
		{ark_dir, "build", opts.package_name, opts.version, installed.binary},
		context.allocator,
	)
	if new_build_dir_err != .None {
		fmt.println("ERROR: failed to construct build directory during existence check")
		os.exit(0)
	}

	if !shared.check_file_or_folder_exists(new_binary_file_to_link) {
		fmt.printfln(
			"%[0]s of version %[1]s does not exist. To install, run:\n\n    ark install %[2]s --version %[1]s\n\n",
			opts.package_name,
			opts.version,
			installed.repo,
		)
		os.exit(1)
	}

	if relink_err := shared.relink_binary_atomic(
		ark_dir,
		installed.binary,
		new_binary_file_to_link,
	); relink_err != nil {
		fmt.eprintfln("ERROR: failed to relink %s: %v", installed.binary, relink_err)
		os.exit(1)
	}
}
