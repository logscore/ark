package commands

import shared "../shared"
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

	// TODO: error handling for the join_path on ALL join_path invokations
	ark_dir, _ := os.join_path({home_dir, ".ark"}, context.allocator)
	defer delete(ark_dir)

	if !shared.check_file_or_folder_exists(ark_dir) {
		fmt.println("Ark is not initialized globally. Run 'ark init' to initialize Ark.")
	}

	switch {
	// For later if it is needed
	case command == "init":
		init_ark(ark_dir, options)
	case command == "install":
		// Run install function
		install_package(ark_dir, options)
	case command == "uninstall":
		// Run uninstall function
		uninstall_package(ark_dir, options)
	case command == "update":
		// Run update function
		update_package(ark_dir, options)
	case command == "list":
	// Validate options
	// run list function
	case command == "use":
		// Validate options
		use_package(ark_dir, options)
	case command == "build":
	//validate options
	// run build function
	case command == "--help" || command == "help":
		shared.print_help("")
	case:
		fmt.printfln("Unknown command: %s\n", command)
		os.exit(1)
	}
}
