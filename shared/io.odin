package shared

import "base:runtime"
import "core:bytes"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

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
	if !check_file_or_folder_exists(sym_link_path) {
		return ""
	}

	// resolve symlink
	resolved_path, sym_read_error := os.read_link(sym_link_path, context.allocator)
	defer delete(resolved_path, context.allocator)
	delete(sym_link_path, context.allocator)

	return strings.clone(resolved_path)
}

// Path of a single installed build artifact. The SHA is its stable identity.
artifact_path :: proc(ark_dir, name, sha, binary: string) -> string {
	path, path_error := os.join_path({ark_dir, "build", name, sha, binary}, context.allocator)
	if path_error != nil {
		fmt.eprintln("ERROR: failed to build artifact path:", path_error)
		os.exit(1)
	}

	return path
}

artifact_exists :: proc(ark_dir, name, sha, binary: string) -> bool {
	path := artifact_path(ark_dir, name, sha, binary)
	defer delete(path)

	return os.is_file(path)
}

// Does bin/<binary> point at this exact commit?
is_active_version :: proc(ark_dir, name, sha, binary: string) -> bool {
	link_target := resolve_symlink_to_path(ark_dir, binary)
	if link_target == "" {
		return false
	}
	defer delete(link_target)

	path := artifact_path(ark_dir, name, sha, binary)
	defer delete(path)

	return link_target == path
}

find_entry :: proc(
	entries: []Entry,
	name, selector: string,
) -> (
	entry: Entry,
	index: int,
	ok: bool,
) {
	index = -1
	for candidate, candidate_index in entries {
		// checks tag name, branch name, sha in that order
		if candidate.name != name ||
		   (selector != "" &&
				   !(entry.version == selector ||
						   entry.ref_name == selector ||
						   (len(selector) >= 7 && strings.starts_with(entry.sha, selector)))) {
			continue
		}

		if !ok || candidate.timestamp >= entry.timestamp {
			entry = candidate
			index = candidate_index
			ok = true
		}
	}
	return
}

read_lock :: proc(
	ark_dir: string,
	allocator: runtime.Allocator = context.allocator,
) -> (
	lock_data: Lock_Data,
	ok: bool,
) {
	ark_lock_path, ark_lock_path_error := os.join_path({ark_dir, "ark.lock"}, context.allocator)
	defer delete(ark_lock_path, context.allocator)
	if ark_lock_path_error != nil {
		fmt.eprintln("ERROR: could not build .ark directory during initialization.")
		return {}, false
	}

	lock_file, read_lock_error := os.read_entire_file_from_path(ark_lock_path, context.allocator)
	defer delete(lock_file, context.allocator)
	if read_lock_error != nil {
		fmt.eprintln("ERROR could not read ark.lock file")
		return {}, false
	}


	cursor := lock_file
	index: u16 = 0
	for line_bytes in bytes.split_iterator(&cursor, []byte{'\n'}) {
		trimmed_line_bytes := bytes.trim_space(line_bytes)
		if len(trimmed_line_bytes) == 0 || bytes.has_prefix(trimmed_line_bytes, []byte{'#'}) {
			index += 1
			continue
		}

		// puts the line bytes into an array of bytes
		parts: [8][]byte
		count: u8 = 0
		for part in bytes.split_iterator(&trimmed_line_bytes, []byte{' '}) {
			if count >= len(parts) {
				fmt.eprintfln("Invalid ark.lock entry at ~/.ark/ark.lock:%i", index + 1)

				free_lock_data(&lock_data, context.allocator)

				return {}, false
			}
			parts[count] = part
			count += 1
		}

		if count != len(parts) {
			fmt.eprintfln("Invalid ark.lock entry at ~/.ark/ark.lock:%i", index + 1)

			free_lock_data(&lock_data, context.allocator)

			return {}, false
		}

		timestamp, ok := strconv.parse_i64(string(parts[5]))
		if !ok {
			fmt.eprintfln("Invalid timestamp at ~/.ark/ark.lock:%i", index + 1)

			free_lock_data(&lock_data, context.allocator)

			return {}, false
		}

		// TODO: dont copy every single property of the entry. Maybe allocate an arena at the beginning and use that, or something. Im not sure actually. The copy can get expensive if someone has many versions installed and wants to install a new one, or want to uninstall/list all of them.
		append(
			&lock_data.data,
			Entry {
				name = strings.clone(string(parts[0]), context.allocator),
				version = strings.clone(string(parts[1]), context.allocator),
				sha = strings.clone(string(parts[2]), context.allocator),
				url = strings.clone(string(parts[3]), context.allocator),
				binary = strings.clone(string(parts[4]), context.allocator),
				timestamp = timestamp,
				ref_kind = strings.clone(string(parts[6]), context.allocator),
				ref_name = strings.clone(string(parts[7]), context.allocator),
			},
		)
		index += 1
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
			"%s %s %s %s %s %d %s %s\n",
			e.name,
			e.version,
			e.sha,
			e.url,
			e.binary,
			e.timestamp,
			e.ref_kind,
			e.ref_name,
		)
	}

	lock_path, _ := os.join_path({ark_dir, "ark.lock"}, context.allocator)
	defer delete(lock_path, context.allocator)

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
		fmt.eprintln("ERROR: could not build .ark directory during initialization.")
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
	// TODO: Error handling
	err := json.unmarshal(user_config_file, &config, allocator = context.allocator)
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
) -> (
	parent: string,
	name: string,
	ok: bool,
) {
	rest := url
	if strings.starts_with(url, "git@") {
		rest = strings.trim_prefix(url, "git@")
		rest, _ = strings.replace(rest, ":", "/", 1, context.temp_allocator)
	} else {
		rest = strings.trim_prefix(url, "https://")
		rest = strings.trim_prefix(rest, "http://")
	}
	rest = strings.trim_suffix(rest, ".git")

	if rest == "" {
		return "", "", false
	}

	segment_count := 0
	cursor := rest
	for seg in strings.split_iterator(&cursor, "/") {
		if seg == "" || seg == "." || seg == ".." {
			return "", "", false
		}
		segment_count += 1
	}

	if segment_count < 2 {
		return "", "", false
	}

	name_index := strings.last_index_byte(rest, '/')
	name = rest[name_index + 1:]

	parent, _ = os.join_path({ark_dir, "repos", rest[:name_index]}, context.allocator)

	return parent, name, true
}

free_lock_data :: proc(lock_data: ^Lock_Data, allocator := context.allocator) {
	assert(lock_data != nil)

	for entry in lock_data.data {
		delete(entry.name, allocator)
		delete(entry.version, allocator)
		delete(entry.sha, allocator)
		delete(entry.url, allocator)
		delete(entry.binary, allocator)
		delete(entry.ref_kind, allocator)
		delete(entry.ref_name, allocator)
	}

	// A dynamic array carries its own allocator, so delete takes no specified allocator
	delete(lock_data.data)
	lock_data.data = nil
}
