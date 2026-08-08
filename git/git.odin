package git

import shared "../shared"

import "core:fmt"
import "core:os"
import "core:strings"

resolve_repo_to_sha :: proc(
	parent_dir: string,
	package_name: string,
	repo_data: shared.Repo,
) -> string {
	cache_dir, _ := os.join_path({parent_dir, package_name}, context.allocator)
	defer delete(cache_dir)

	repo_exists := shared.check_file_or_folder_exists(cache_dir)

	// The repository cache is independent from whether the package is
	// already installed. Clone only when the cache does not exist.
	if !repo_exists {
		_ = os.make_directory_all(parent_dir)
		ok := clone_bare_copy(repo_data.url, package_name, parent_dir)
		if !ok {
			// fmt.printfln("ERROR: failed to clone to target directory: %s", full_repo_dir)
			os.exit(1)
		}

		fmt.println("\nSuccessfully cloned to:", cache_dir)
	}

	if !fetch_remotes_and_tags(cache_dir) {
		fmt.eprintln("Failed to fetch remote branches and tags.")
		os.exit(1)
	}

	ref_sha, spec_ok := resolve_spec_to_sha(cache_dir, repo_data.spec)
	if !spec_ok {
		fmt.eprintfln("Repository has no valid ref for version: %s", repo_data.spec)
		os.exit(1)
	}

	return ref_sha
}

clone_bare_copy :: proc(repo_url: string, repo_name: string, repos_dir: string) -> bool {
	args := []string{"git", "clone", "--bare", "--filter=blob:none", repo_url, repo_name}

	// Needs PATH for ssh
	env, _ := os.environ(context.allocator)

	p, start_err := os.process_start(
		os.Process_Desc {
			working_dir = repos_dir,
			command = args,
			env = env,
			stdin = os.stdin,
			stdout = os.stdout,
			stderr = os.stderr,
		},
	)
	if start_err != nil {
		return false
	}
	delete(env)

	state, wait_err := os.process_wait(p)
	if wait_err != nil {
		return false
	}
	if state.exit_code != 0 {
		return false
	}

	return true
}

fetch_remotes_and_tags :: proc(full_repo_dir: string) -> bool {
	args := []string {
		"git",
		"-C",
		full_repo_dir,
		"fetch",
		"origin",
		"+refs/heads/*:refs/heads/*",
		"+refs/tags/*:refs/tags/*",
		"--prune",
	}

	p, start_err := os.process_start({command = args})
	if start_err != nil {
		return false
	}

	state, wait_err := os.process_wait(p)
	if wait_err != nil || state.exit_code != 0 {
		return false
	}

	fmt.println("Fetched remote tags and branches into local repo.")
	return true
}

resolve_spec_to_sha :: proc(full_repo_dir: string, spec: string) -> (ref_sha: string, ok: bool) {
	refs := [3]string{"refs/tags/", "refs/heads/", ""}

	for ref in refs {
		read_pipe, write_pipe, pipe_err := os.pipe()
		if pipe_err != nil {
			return "", false
		}

		args := []string {
			"git",
			"-C",
			full_repo_dir,
			"rev-parse",
			"--verify",
			"--quiet",
			"--end-of-options",
			strings.concatenate({ref, spec, "^{commit}"}),
		}

		process, start_err := os.process_start(
			os.Process_Desc {
				command = args,
				stdin = os.stdin,
				stdout = write_pipe,
				stderr = os.stderr,
			},
		)

		os.close(write_pipe)

		if start_err != nil {
			os.close(read_pipe)
			return "", false
		}

		state, wait_err := os.process_wait(process)
		if wait_err != nil || state.exit_code != 0 {
			os.close(read_pipe)
			continue
		}

		pipe_data, read_err := os.read_entire_file_from_file(read_pipe, context.allocator)
		os.close(read_pipe)

		if read_err != nil {
			return "", false
		}
		defer delete(pipe_data, context.allocator)

		sha := strings.trim_space(string(pipe_data))
		return strings.clone(sha), true
	}

	return "", false
}

compare_fetched_sha_to_lock_sha :: proc(ref_sha: string, lock_data: shared.Lock_Data) {
	for data in lock_data.data {
		if ref_sha == data.sha {
			fmt.eprintfln(
				"Package already exists based on the resolved hash: %s. To bypass this check, run the same command with --force",
				ref_sha,
			)
			os.exit(1)
		}
	}
	return
}

checkout_to_sha :: proc(
	ark_dir: string,
	ref_sha: string,
	cache_parent_dir: string,
	package_name: string,
) -> (
	string,
	bool,
) {
	tmp_dir, tmp_dir_error := os.join_path({ark_dir, "tmp"}, context.allocator)
	defer delete(tmp_dir, context.allocator)

	if tmp_dir_error != nil {
		fmt.println("Failed to build tmp directory during fetch.")
		os.exit(1)
	}

	full_tmp_build_dir, err := os.mkdir_temp(
		tmp_dir,
		strings.concatenate({package_name, "-"}),
		context.allocator,
	)
	if err != nil {
		fmt.eprintln("failed to create temp build directory:", err)
		return "", false
	}
	defer delete(full_tmp_build_dir)

	full_repo_path, _ := os.join_path({cache_parent_dir, package_name}, context.allocator)
	defer delete(full_repo_path, context.allocator)

	// git worktree add \
	//   --detach \
	//   "$tmp_dir" \
	//   "$commit" \
	args := []string{"git", "worktree", "add", "--detach", full_tmp_build_dir, ref_sha}

	p, start_err := os.process_start(
		os.Process_Desc {
			working_dir = full_repo_path,
			command = args,
			stdin = os.stdin,
			stdout = os.stdout,
			stderr = os.stderr,
		},
	)
	if start_err != nil {
		fmt.eprintln("failed to start git:", start_err)
		os.exit(1)
	}

	state, wait_err := os.process_wait(p)
	if wait_err != nil {
		fmt.eprintln("failed to wait for git:", wait_err)
		os.exit(1)
	}
	if state.exit_code != 0 {
		fmt.eprintln("git failed:", state)
		os.exit(1)
	}

	return strings.clone(full_tmp_build_dir), true
}

ensure_git :: proc() {
	_, _, _, error := os.process_exec({command = {"git", "--version"}}, context.allocator)

	if error != nil {
		fmt.eprintfln("ERROR: git is not installed on system PATH")
		os.exit(1)
	}
}
