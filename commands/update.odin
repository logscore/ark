package commands

import git "../git"
import shared "../shared"

import "core:flags"
import "core:fmt"
import "core:os"
import "core:time"

Update_Options :: struct {
	package_name: string `args:"name=package,pos=0,required"`,
	force:        bool `args:"name=force"`,
	version:      string `args:"name=version"`,
}

update_package :: proc(ark_dir: string, options: []string) -> (exit_code: int) {
	if !git.ensure_git() {
		return 1
	}

	opts: Update_Options
	err := flags.parse(&opts, options, .Unix)
	switch v in err {
	case flags.Help_Request:
		shared.print_help("update")
		return 0
	case flags.Parse_Error:
		fmt.println(v.message)
		return 1
	case flags.Open_File_Error:
		fmt.println("Could not open", v.filename)
		return 1
	case flags.Validation_Error:
		fmt.println(v.message)
		return 1
	}

	lock_data, lock_ok := shared.read_lock(ark_dir, context.allocator)
	if !lock_ok {
		return 1
	}

	defer shared.free_lock_data(&lock_data, context.allocator)

	latest, _, installed := shared.find_entry(lock_data.data[:], opts.package_name, "")
	if !installed {
		fmt.printfln(`%s not installed, use 'ark install'`, opts.package_name)
		return 1
	}

	parent_path: string
	url_derived_name: string
	ok: bool
	if parent_path, url_derived_name, ok = shared.repo_path_from_url(ark_dir, latest.url); !ok {
		fmt.printfln("Invalid repo url: %s\n", latest.url)
		return 1
	}
	defer delete(parent_path)

	repo_data := shared.Repo {
		url         = latest.url,
		name        = url_derived_name,
		spec        = opts.version,
		default_ref = false,
	}
	if opts.version == "" {
		if latest.ref_kind == shared.REF_KIND_BRANCH {
			repo_data.spec = latest.ref_name
		} else {
			repo_data.default_ref = true
		}
	}

	ref_sha, ref_kind, ref_name: string
	if ref_sha, ref_kind, ref_name, ok = git.resolve_repo_to_sha(
		parent_path,
		url_derived_name,
		repo_data,
	); !ok {
		return 1
	}

	version := repo_data.spec
	if repo_data.default_ref {
		version = ref_sha[:7]
	}

	matched, matched_index, found := shared.find_entry(
		lock_data.data[:],
		opts.package_name,
		ref_sha,
	)
	if found {
		artifact_found := shared.artifact_exists(
			ark_dir,
			matched.name,
			matched.sha,
			matched.binary,
		)
		if artifact_found && !opts.force {
			if shared.is_active_version(ark_dir, matched.name, matched.sha, matched.binary) {
				fmt.printfln(
					"Package '%[0]s' of version '%[1]s' is already installed and active.\n\nPass --force to rebuild it.",
					url_derived_name,
					matched.version,
				)
				return 1
			}

			target := shared.artifact_path(ark_dir, matched.name, matched.sha, matched.binary)
			defer delete(target)
			if relink_err := shared.relink_binary_atomic(ark_dir, matched.binary, target);
			   relink_err != nil {
				return 1
			}

			fmt.printfln(
				"Package '%[0]s' of version '%[1]s' is installed. It is now active.",
				url_derived_name,
				matched.version,
			)
			return 0
		}

		if !artifact_found {
			fmt.printfln(
				"Package '%[0]s' of version '%[1]s' is in the lock file, but its binary is missing. Installing from the lock file...",
				url_derived_name,
				matched.version,
			)
		}

		tmp_build_dir, checkout_ok := git.checkout_to_sha(
			ark_dir,
			ref_sha,
			parent_path,
			url_derived_name,
		)
		if !checkout_ok {
			fmt.eprintfln("Failed to checkout ref %s.", ref_sha[:7])
			return 1
		}
		defer git.remove_worktree(parent_path, url_derived_name, tmp_build_dir)

		fmt.println("Running builder")
		fmt.println("Updating lock")
		lock_data.data[matched_index].timestamp = time.to_unix_seconds(time.now())
		if !shared.write_lock(ark_dir, lock_data.data[:]) {
			fmt.println("ERROR: failed to write ark.lock")
			return 1
		}
		fmt.println("Running installer")
		return 0
	}

	tmp_build_dir, checkout_ok := git.checkout_to_sha(
		ark_dir,
		ref_sha,
		parent_path,
		url_derived_name,
	)
	if !checkout_ok {
		fmt.eprintln("Failed to checkout SHA to temporary build directory.")
		return 1
	}
	defer git.remove_worktree(parent_path, url_derived_name, tmp_build_dir)

	fmt.println("Running builder")
	fmt.println("Updating lock")
	append(
		&lock_data.data,
		shared.Entry {
			name = url_derived_name,
			version = version,
			sha = ref_sha,
			url = latest.url,
			binary = "placeholder",
			timestamp = time.to_unix_seconds(time.now()),
			ref_kind = ref_kind,
			ref_name = ref_name,
		},
	)
	if !shared.write_lock(ark_dir, lock_data.data[:]) {
		fmt.println("ERROR: failed to write ark.lock")
		return 1
	}
	fmt.println("Running installer")

	return 0
}
