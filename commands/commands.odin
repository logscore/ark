package commands

import "../shared"

import "core:fmt"
import "core:os"

run :: proc(command: string, options: []string) {
	home_dir, error := os.user_home_dir(context.allocator)
	defer delete(home_dir, context.allocator)
	if error != nil {
		// Fallback to manual path construction
		fmt.println("Failed to get user home directory.")
		os.exit(1)
	}

	// check dirs & lock exist
	items_to_check := [5]string{"build", "repos", "tmp", "bin", "ark.lock"}

	for item in items_to_check {
		if !shared.check_file_or_folder_exists(home_dir, []string{item}) {
			// TODO: lazy init the .ark directory and its sub dirs/files
			// fmt.eprintln(`ERROR: .ark directory is not initialized properly. Please run "ark init" to setup ark.`)
			fmt.eprintln(
				`ERROR: .ark directory is not initialized properly. Please run the install command and try again.`,
			)
			os.exit(1)
		}
	}

	switch {
	// For later if it is needed
	// case command == "init":
	// 	init_ark(options)
	case command == "install":
		// Run install function
		install_package(home_dir, options)
	case command == "uninstall":
	// Run uninstall function
	case command == "update":
		// Run update function
		update_package(home_dir, options)
	case command == "list":
	// Validate options
	// run list function
	case command == "set":
	// Validate options
	// run set function
	case command == "build":
	//validate options
	// run build function
	case:
		fmt.printfln("Unknown command: %s\n", command)
		os.exit(1)
	}
}
