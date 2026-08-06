package commands

import "core:flags"
import "core:fmt"
import "core:os"

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

	// Is the requested version already the active one?
	if shared.is_active_version(ark_dir, opts.package_name, opts.version, installed.binary) {
		fmt.printfln("%[0]s of version %[1]s is already active.", opts.package_name, opts.version)
		return
	}

	if !shared.artifact_exists(ark_dir, opts.package_name, opts.version, installed.binary) {
		fmt.printfln(
			"%[0]s of version %[1]s does not exist. To install, run:\n\n    ark install %[2]s --version %[1]s\n\n",
			opts.package_name,
			opts.version,
			installed.repo,
		)
		os.exit(1)
	}

	new_binary_file_to_link := shared.artifact_path(
		ark_dir,
		opts.package_name,
		opts.version,
		installed.binary,
	)
	defer delete(new_binary_file_to_link)

	if relink_err := shared.relink_binary_atomic(
		ark_dir,
		installed.binary,
		new_binary_file_to_link,
	); relink_err != nil {
		os.exit(1)
	}
}
