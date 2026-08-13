package perf

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:prof/spall"
import "core:sync"

when ODIN_DEBUG {
	@(thread_local)
	trace_buffer: spall.Buffer
	trace_context: spall.Context
	trace_backing: [spall.BUFFER_DEFAULT_SIZE]u8
	trace_active: bool

	@(no_instrumentation)
	trace_start :: proc() {
		ctx: spall.Context
		ok: bool
		ctx, ok = spall.context_create_with_scale("ark.spall", false, 1)
		if !ok {
			fmt.eprintln("Failed to create ark.spall trace.")
			return
		}

		buffer, buffer_ok := spall.buffer_create(
			trace_backing[:],
			u32(sync.current_thread_id()),
			u32(os.get_pid()),
		)
		if !buffer_ok {
			spall.context_destroy(&ctx)
			fmt.eprintln("Failed to create Spall trace buffer.")
			return
		}

		trace_context = ctx
		trace_buffer = buffer
		trace_active = true
		spall._buffer_name_process(&trace_context, &trace_buffer, "ark")
		spall._buffer_name_thread(&trace_context, &trace_buffer, "main")
		spall._buffer_begin(&trace_context, &trace_buffer, "main")
	}

	@(no_instrumentation)
	trace_stop :: proc() {
		if !trace_active {
			return
		}

		spall._buffer_end(&trace_context, &trace_buffer)
		trace_active = false
		spall.buffer_destroy(&trace_context, &trace_buffer)
		spall.context_destroy(&trace_context)
	}

	@(instrumentation_enter)
	trace_enter :: proc "contextless" (_, _: rawptr, location: runtime.Source_Code_Location) {
		if trace_active {
			spall._buffer_begin(&trace_context, &trace_buffer, "", "", location)
		}
	}

	@(instrumentation_exit)
	trace_exit :: proc "contextless" (_, _: rawptr, _: runtime.Source_Code_Location) {
		if trace_active {
			spall._buffer_end(&trace_context, &trace_buffer)
		}
	}
}
