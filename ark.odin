package main

import "core:fmt"
import "core:os"

import "commands"
import "help"

main :: proc() {
	if len(os.args) < 2 {
		fmt.println(help.default_help)
		os.exit(1)
	}

	// Check that git is installed maybe move this to only the git dependant operations (install, update)
	_, _, _, error := os.process_exec({command = {"git", "--version"}}, context.allocator)

	if error != nil {
		fmt.eprintfln("ERROR: git is not installed on system PATH")
		os.exit(1)
	}

	args := os.args
	command := args[1]
	options := args[2:]

	commands.run(command, options)
}
