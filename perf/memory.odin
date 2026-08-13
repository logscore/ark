package perf

import "core:fmt"
import "core:mem"

when ODIN_DEBUG {
	memory_tracker: mem.Tracking_Allocator
	memory_allocator: mem.Allocator
	memory_active: bool

	@(no_instrumentation)
	memory_start :: proc() -> mem.Allocator {
		backing := context.allocator
		mem.tracking_allocator_init(&memory_tracker, backing, backing)
		memory_allocator = mem.tracking_allocator(&memory_tracker)
		memory_active = true
		return memory_allocator
	}

	@(no_instrumentation)
	memory_stop :: proc() {
		if !memory_active {
			return
		}

		memory_active = false
		context.allocator = memory_tracker.backing

		fmt.eprintfln(
			"Memory: allocated %m in %d allocations; freed %m in %d frees; peak %m; live %m in %d allocations.",
			memory_tracker.total_memory_allocated,
			memory_tracker.total_allocation_count,
			memory_tracker.total_memory_freed,
			memory_tracker.total_free_count,
			memory_tracker.peak_memory_allocated,
			memory_tracker.current_memory_allocated,
			len(memory_tracker.allocation_map),
		)

		for _, leak in memory_tracker.allocation_map {
			fmt.eprintfln("%v leaked %m", leak.location, leak.size)
		}

		mem.tracking_allocator_destroy(&memory_tracker)
	}
}
