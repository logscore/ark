package perf

import "core:mem"

when ODIN_DEBUG {
	@(no_instrumentation)
	start :: proc() -> mem.Allocator {
		allocator := memory_start()
		context.allocator = allocator
		trace_start()
		return allocator
	}

	@(no_instrumentation)
	stop :: proc() {
		trace_stop()
		memory_stop()
	}
}
