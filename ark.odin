package main

import "core:fmt"
import "core:os"

import "commands"
import "shared"

main :: proc() {
	if len(os.args) < 2 {
		fmt.println(shared.default_help)
		os.exit(1)
	}

	args := os.args
	command := args[1]
	options := args[2:]

	commands.run(command, options)

	// NOTE: We might want to adjsut the logic paths so that all exits happen here. We can instead return a code and maybe an error and it will surface here. We handle the error and print, then exit with the code
	os.exit(0)
}
