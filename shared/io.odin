#+feature dynamic-literals
package shared

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

import "../shared"

// I do not like this implementation. I would prefer we simply pass in the values in a []string and test dumbly
check_file_or_folder_exists :: proc(home_dir: string, item_to_check: []string) -> bool {
	// We should probably not use dynamic literals. i just dont get it yet
	full_path := [dynamic]string{home_dir, ".ark"}
	append(&full_path, ..item_to_check)
	joined_path, error := os.join_path(full_path[:], context.allocator)
	delete(full_path)

	if error != nil {
		fmt.println("Failed to join .ark folders for validation.")
		return false
	}
	if os.is_dir(joined_path) {
		return true
	}
	if os.is_file(joined_path) {
		return true
	}
	return false
}

resolve_binary_version :: proc(home_dir: string, binary_name: string) -> string {
	// This takes in a binary name, and returns the path that the symlink points to

	// Verify the binary exists. If not, its not installed. We need to use the packages bin name
	if !shared.check_file_or_folder_exists(home_dir, []string{"bin", binary_name}) {
		return ""
	}

	// resolve symlink
	resolved_path, sym_read_error := os.read_link(binary_name, context.allocator)
	defer delete(resolved_path, context.allocator)

	fmt.println(resolved_path)

	return strings.clone(resolved_path)
}

read_lock :: proc(home_dir: string) -> (lock_data: Lock_Data, ok: bool) {
	ark_lock_path, ark_lock_path_error := os.join_path(
		{home_dir, ".ark", "ark.lock"},
		context.allocator,
	)
	defer delete(ark_lock_path, context.allocator)
	if ark_lock_path_error != nil {
		fmt.println("Failed to build .ark directory during initialization.")
		return {}, false
	}

	lock_file, read_lock_error := os.read_entire_file_from_path(ark_lock_path, context.allocator)
	defer delete(lock_file, context.allocator)
	if read_lock_error != nil {
		fmt.eprintln("ERROR could not read ark.lock file")
		return {}, false
	}

	lines := strings.split(string(lock_file), "\n", context.allocator)
	defer delete(lines, context.allocator)

	for &line, index in lines {
		line = strings.trim_space(line)
		if line == "" || strings.starts_with(line, "#") {
			continue
		}

		parts := strings.fields(line, context.allocator)
		if len(parts) != 5 {
			fmt.eprintfln("invalid ark.lock entry at ~/.ark/ark.lock:%i", index + 1)
			delete(parts, context.allocator)
			delete(lock_data.data) // cleanup on error
			return {}, false
		}

		append(
			&lock_data.data,// There might be a memory bug where the lock_data is passed to caller. We delete it tho, so idk
			shared.Entry {
				name = strings.clone(parts[0], context.allocator),
				version = strings.clone(parts[1], context.allocator),
				sha = strings.clone(parts[2], context.allocator),
				repo = strings.clone(parts[3], context.allocator),
				binary = strings.clone(parts[4], context.allocator),
			},
		)
		delete(parts, context.allocator)
	}

	return lock_data, true
}

read_user_config :: proc(home_dir: string) -> (User_Config, bool) {
	// Read user config from ~/.ark into memory
	user_config_path, user_config_path_error := os.join_path(
		{home_dir, ".ark", "ark.json"},
		context.allocator,
	)
	defer delete(user_config_path, context.allocator)

	if user_config_path_error != nil {
		fmt.println("Failed to build .ark directory during initialization.")
		return User_Config{}, false
	}

	user_config_file, read_user_config_error := os.read_entire_file_from_path(
		user_config_path,
		context.allocator,
	)
	defer delete(user_config_file, context.allocator)

	if read_user_config_error != nil {
		switch {
		case read_user_config_error == .Not_Exist:
			// Create it in a non blocking thread
			fmt.println("Local user build config file not set.")
		case:
			return User_Config{}, false
		}
	}

	config: User_Config
	err := json.unmarshal(user_config_file, &config)

	return config, true
}
