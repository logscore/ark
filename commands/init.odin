// Unsure if i really even want this yet. We'll leave it wired for now
package commands

import "core:flags"
import "core:os"

Init_Options :: struct {
	force:       bool `args: "name=force" usage: "Writes over existing .ark folders and files"`,
	add_to_path: bool `args: "name=add-to-path" usage: "adds ark to user path automatically"`,
}

init_ark :: proc(options: []string) {
	init_options: Init_Options
	flags.parse_or_exit(&init_options, options, .Unix)

	init_ark_dirs(init_options.force)
	if init_options.add_to_path {
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
