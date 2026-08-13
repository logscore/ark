package commands

import shared "../shared"
import "core:fmt"
import "core:os"

run :: proc(command: string, options: []string) -> (exit_code: int) {
	home_dir, error := os.user_home_dir(context.allocator)
	defer delete(home_dir, context.allocator)
	if error != nil {
		// Fallback to manual path construction
		fmt.println("Failed to get user home directory.")
		exit_code = 1
	}

	// TODO: error handling for the join_path on ALL join_path invokations
	ark_dir: string
	ark_dir, error = os.join_path({home_dir, ".ark"}, context.allocator)
	defer delete(ark_dir)
	if error != nil {
		fmt.println("Failed to build .ark path.")
		exit_code = 1
	}


	if !shared.check_file_or_folder_exists(ark_dir) {
		fmt.println("Ark is not initialized globally. Run 'ark init' to initialize Ark.")
		exit_code = 1
	}

	switch {
	// For later if it is needed
	case command == "init":
		exit_code = init_ark(ark_dir, options)
	case command == "install":
		// Run install function
		exit_code = install_package(ark_dir, options)
	case command == "uninstall":
		// Run uninstall function
		exit_code = uninstall_package(ark_dir, options)
	case command == "update":
		// Run update function
		exit_code = update_package(ark_dir, options)
	case command == "list":
	// Validate options
	// run list function
	case command == "use":
		// Validate options
		exit_code = use_package(ark_dir, options)
	case command == "build":
	//validate options
	// run build function
	case command == "--help" || command == "help":
		shared.print_help("")
		exit_code = 0
	case:
		fmt.printfln("Unknown command: %s\n", command)
		exit_code = 1
	}

	return exit_code
}
