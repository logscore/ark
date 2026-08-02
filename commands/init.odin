// Unsure if i really even want this yet. We'll leave it wired for now
package commands

import "core:flags"
import "core:fmt"
import "core:os"

import "../shared"

Init_Options :: struct {
	force:       bool `args:"name=force"`,
	add_to_path: bool `args:"name=add-to-path"`,
}

init_ark :: proc(options: []string) {
	opts: Init_Options
	err := flags.parse(&opts, options, .Unix)
	switch v in err {
	case flags.Help_Request:
		shared.print_help("init")
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

	init_ark_dirs(opts.force)

	if opts.add_to_path {
		add_ark_to_path()
	}
	os.exit(0)
}

init_ark_dirs :: proc(force: bool) {
	// is force is true, just add all the folders and files, overwriting existing ones. Clean .ark dir too. maybe just delete it.
	// If not, skip the existing items and only write the missing ones
}

add_ark_to_path :: proc() {
	when ODIN_OS == .Windows {
		// Add ark to windows path. Idk how to do this or if symlinks messes with it.
	} else when ODIN_OS == .Darwin || ODIN_OS == .Linux {
		// os.get_env("SHELL")
		// based on the result, append to the file. Get confirmation from user before doing this.
		// If they deny, print the command they should run in a shell.
	}
}
