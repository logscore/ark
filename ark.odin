package main

import "core:fmt"
import "core:os"

import "commands"
import "perf"
import "shared"

main :: proc() {
	when ODIN_DEBUG {
		context.allocator = perf.start()
	}

	exit_code := 0
	if len(os.args) < 2 {
		fmt.println(shared.default_help)
		exit_code = 1
	} else {
		args := os.args
		command := args[1]
		options := args[2:]

		exit_code = commands.run(command, options)
	}

	when ODIN_DEBUG {
		perf.stop()
	}

	os.exit(exit_code)
}
