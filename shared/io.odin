
#+feature dynamic-literals
package shared

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

import "../shared"

check_file_or_folder_exists :: proc(path_to_file_or_folder: string) -> bool {
	if os.is_dir(path_to_file_or_folder) {
		return true
	}
	if os.is_file(path_to_file_or_folder) {
		return true
	}
	return false
}

// This takes in a binary name, and returns the path that the symlink points to
resolve_symlink_to_path :: proc(ark_dir: string, binary_name: string) -> string {
	sym_link_path, _ := os.join_path({ark_dir, "bin", binary_name}, context.allocator)

	// Verify the binary exists. If not, its not installed. We need to use the packages bin name
	if !shared.check_file_or_folder_exists(sym_link_path) {
		return ""
	}

	// resolve symlink
	resolved_path, sym_read_error := os.read_link(sym_link_path, context.allocator)
	defer delete(resolved_path, context.allocator)
	delete(sym_link_path, context.allocator)

	return strings.clone(resolved_path)
}

// Path of a single installed build artifact. Returns OS specific path to artifact.
artifact_path :: proc(ark_dir, name, version, binary: string) -> string {
	path, path_error := os.join_path({ark_dir, "build", name, version, binary}, context.allocator)
	if path_error != nil {
		fmt.eprintln("ERROR: failed to build artifact path:", path_error)
		os.exit(1)
	}

	return path
}

// Is the artifact of this exact version on disk? Checks its a file, not dir
artifact_exists :: proc(ark_dir, name, version, binary: string) -> bool {
	path := artifact_path(ark_dir, name, version, binary)
	defer delete(path)

	return os.is_file(path)
}

// Does bin/<binary> point at this exact version? The compare is valid because
// every link holds an absolute artifact_path value.
is_active_version :: proc(ark_dir, name, version, binary: string) -> bool {
	link_target := resolve_symlink_to_path(ark_dir, binary)
	if link_target == "" {
		return false
	}
	defer delete(link_target)

	path := artifact_path(ark_dir, name, version, binary)
	defer delete(path)

	return link_target == path
}

read_lock :: proc(ark_dir: string) -> (lock_data: Lock_Data, ok: bool) {
	ark_lock_path, ark_lock_path_error := os.join_path({ark_dir, "ark.lock"}, context.allocator)
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
		if len(parts) != 6 {
			fmt.eprintfln("invalid ark.lock entry at ~/.ark/ark.lock:%i", index + 1)
			delete(parts, context.allocator)
			delete(lock_data.data)
			return {}, false
		}

		timestamp, ok := strconv.parse_i64(parts[5])
		if !ok {
			fmt.eprintfln("invalid timestamp at ~/.ark/ark.lock:%i", index + 1)
			delete(lock_data.data)
			return {}, false
		}

		append(
			&lock_data.data, // There might be a memory bug where the lock_data is passed to caller. We delete it tho, so idk
			shared.Entry {
				name = strings.clone(parts[0], context.allocator),
				version = strings.clone(parts[1], context.allocator),
				sha = strings.clone(parts[2], context.allocator),
				repo = strings.clone(parts[3], context.allocator),
				binary = strings.clone(parts[4], context.allocator),
				timestamp = timestamp,
			},
		)
		delete(parts, context.allocator)
	}

	return lock_data, true
}

write_lock :: proc(ark_dir: string, entries: []Entry) -> bool {
	sb: strings.Builder
	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)

	for e in entries {
		fmt.sbprintf(
			&sb,
			"%s %s %s %s %s %d\n",
			e.name,
			e.version,
			e.sha,
			e.repo,
			e.binary,
			e.timestamp,
		)
	}

	lock_path, _ := os.join_path({ark_dir, "ark.lock"}, context.allocator)
	defer delete(lock_path)

	file_write_err := os.write_entire_file(lock_path, transmute([]byte)strings.to_string(sb))

	return file_write_err == nil
}

read_user_config :: proc(ark_dir: string) -> (User_Config, bool) {
	// Walk from local to the .ark generated ark.json to the .git repo provided one

	first_found_config: string
	// Read user config into memory
	user_config_path, user_config_path_error := os.join_path(
		{ark_dir, "ark.json"},
		context.allocator,
	)
	defer delete(user_config_path, context.allocator)

	if user_config_path_error != nil {
		fmt.println("Failed to build .ark directory during initialization.")
		return User_Config{}, false
	}

	user_config_file, user_config_error := os.read_entire_file_from_path(
		user_config_path,
		context.allocator,
	)

	if user_config_error != nil {
		// TODO: eventually handle all the error cases
		// Create it in a non blocking thread
		fmt.println("Local user build config file not set.")
		return User_Config{}, false
	}

	config: User_Config
	err := json.unmarshal(user_config_file, &config)
	defer delete(user_config_file, context.allocator)

	return config, true
}

relink_binary_atomic :: proc(
	ark_dir: string,
	binary_name: string,
	new_target: string,
) -> os.Error {
	// Atomic relinking for symlink
	new_file, _ := os.join_path({ark_dir, "bin", binary_name}, context.allocator)
	tmp_file := strings.concatenate({new_file, ".tmp"})

	defer delete(new_file)
	defer delete(tmp_file)

	// clears stale tmp
	// TODO: Error handling?
	os.remove(tmp_file)

	if err := os.symlink(new_target, tmp_file); err != nil {
		fmt.printfln("ERROR: failed to create symlink %s: %v", binary_name, err)
		return err
	}
	if err := os.rename(tmp_file, new_file); err != nil {
		os.remove(tmp_file)
		fmt.printfln("ERROR: failed to relink %s: %v", binary_name, err)
		return err
	}

	return nil
}
repo_path_from_url :: proc(
	ark_dir: string,
	url: string,
	allocator := context.allocator,
) -> string {
	rest := url
	if strings.starts_with(url, "git@") {
		rest = strings.trim_prefix(url, "git@")
		rest, _ = strings.replace(rest, ":", "/", 1)
	} else {
		rest = strings.trim_prefix(url, "https://")
	}

	segments := strings.split(rest, "/", context.temp_allocator)
	if len(segments) < 2 {
		return ""
	}

	parts := make([dynamic]string, 0, len(segments) + 2, context.temp_allocator)
	append(&parts, ark_dir, "repos")
	append(&parts, ..segments)

	result, _ := os.join_path(parts[:], allocator)
	return result
}
