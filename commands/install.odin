package commands

import "core:flags"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:time"

import builder "../builder"
import git "../git"
import shared "../shared"

Install_Options :: struct {
	repo_url: string `args:"name=git_url,pos=0,required"`,
	version:  string `args:"name=version"`,
	force:    bool `args:"name=force"`,
}

install_package :: proc(ark_dir: string, options: []string) {
	git.ensure_git()

	opts: Install_Options
	err := flags.parse(&opts, options, .Unix)
	switch v in err {
	case flags.Help_Request:
		shared.print_help("install")
		os.exit(0)
	case flags.Parse_Error:
		fmt.println(v.message)
		os.exit(1)
	case flags.Open_File_Error:
		fmt.println("Could not open", v.filename)
		os.exit(1)
	case flags.Validation_Error:
		fmt.println(v.message)
		os.exit(1)
	}

	repo_data := shared.Repo {
		url         = "",
		name        = "",
		spec        = opts.version,
		default_ref = opts.version == "",
	}

	// Sanitize url
	normalized_url := strings.trim(strings.trim_space(opts.repo_url), "/")

	// parse url.
	// TODO: eventually support bare github.com/user/tool or user/tool
	scheme, host, full_path, _, _ := net.split_url(normalized_url)

	base_path := strings.split(full_path, "@")[0]
	if scheme == "" && strings.starts_with(host, "git@") {
		repo_data.url = strings.concatenate({host, strings.split(full_path, "@")[0]})
	} else if scheme == "https" {
		repo_data.url = strings.concatenate({scheme, "://", host, base_path})
	} else {
		fmt.printfln("Invalid repo url: %s\n", opts.repo_url)
		os.exit(1)
	}

	parent_path: string
	ok: bool
	if parent_path, repo_data.name, ok = shared.repo_path_from_url(
		ark_dir,
		normalized_url,
		context.allocator,
	); !ok {
		fmt.printfln("Invalid repo url: %s\n", opts.repo_url)
		os.exit(1)
	}

	defer delete(parent_path)

	// Fetch refs and resolve the requested tag, branch, or commit.
	ref_sha, ref_kind, ref_name := git.resolve_repo_to_sha(parent_path, repo_data.name, repo_data)

	if repo_data.default_ref {
		repo_data.spec = ref_sha[:7]
	}

	lock_data, lock_ok := shared.read_lock(ark_dir)
	if !lock_ok {
		os.exit(1)
	}

	installed_index := -1
	for line, index in lock_data.data {
		// TODO: Add a --name/--alias flag to alias packages with the same name.
		if line.name == repo_data.name &&
		   line.sha == ref_sha &&
		   (installed_index == -1 || line.timestamp >= lock_data.data[installed_index].timestamp) {
			installed_index = index
		}
	}

	// The SHA is the installed artifact identity.
	if installed_index >= 0 {
		entry := lock_data.data[installed_index]

		// Is the artifact of this exact version on disk?
		if shared.artifact_exists(ark_dir, entry.name, entry.sha, entry.binary) {
			// Is --force true?
			if opts.force {
				// pull build and install
				tmp_build_dir, checkout_ok := git.checkout_to_sha(
					ark_dir,
					ref_sha,
					parent_path,
					repo_data.name,
				)
				if !checkout_ok {
					fmt.eprintln(
						"Failed to checkout ref %s to temporary build directory.",
						ref_sha[:7],
					)
					os.exit(1)
				}
				defer git.remove_worktree(parent_path, repo_data.name, tmp_build_dir)

				// run builder
				fmt.println("Running builder")
				binary, artifact_path, error := builder.build_package(
					ark_dir,
					tmp_build_dir,
					repo_data.name,
				)

				// run lock updater
				fmt.println("Updating lock")
				lock_data.data[installed_index].timestamp = time.to_unix_seconds(time.now())

				if !shared.write_lock(ark_dir, lock_data.data[:]) {
					fmt.println("ERROR: failed to write ark.lock")
					os.exit(1)
				}

				// run installer
				fmt.println("Running installer")
			} else {
				// The version is on disk. Activate it, or report that it is active.
				if shared.is_active_version(ark_dir, entry.name, entry.sha, entry.binary) {
					fmt.printfln(
						"Package '%[0]s' of version '%[1]s' is already installed and active.\n\nPass --force to rebuild it.",
						repo_data.name,
						entry.version,
					)
					os.exit(1)
				}

				target := shared.artifact_path(ark_dir, entry.name, entry.sha, entry.binary)
				defer delete(target)

				if relink_err := shared.relink_binary_atomic(ark_dir, entry.binary, target);
				   relink_err != nil {
					os.exit(1)
				}

				fmt.printfln(
					"Package '%[0]s' of version '%[1]s' is installed. It is now active.",
					repo_data.name,
					entry.version,
				)
			}
			// Is artifact not on disk?
		} else {
			// warn the user, and build, and install anyways
			fmt.printfln(
				"Package '%[0]s' of version '%[1]s' is in lock file, but no binary can be found. Installing package from lock file...\n",
				repo_data.name,
				entry.version,
			)

			tmp_build_dir, checkout_ok := git.checkout_to_sha(
				ark_dir,
				ref_sha,
				parent_path,
				repo_data.name,
			)
			if !checkout_ok {
				fmt.eprintln(
					"Failed to checkout ref %s to temporary build directory.",
					ref_sha[:7],
				)
				os.exit(1)
			}
			defer git.remove_worktree(parent_path, repo_data.name, tmp_build_dir)

			// run builder
			fmt.println("Running builder")
			binary, artifact_path, error := builder.build_package(
				ark_dir,
				tmp_build_dir,
				repo_data.name,
			)

			// run lock updater
			fmt.println("Updating lock")
			lock_data.data[installed_index].timestamp = time.to_unix_seconds(time.now())

			if !shared.write_lock(ark_dir, lock_data.data[:]) {
				fmt.println("ERROR: failed to write ark.lock")
				os.exit(1)
			}

			// run installer
			fmt.println("Running installer")
		}
	} else { 	// Sha is not in lock. New version
		// checkout to spec, build, append lock file, install
		tmp_build_dir, checkout_ok := git.checkout_to_sha(
			ark_dir,
			ref_sha,
			parent_path,
			repo_data.name,
		)
		if !checkout_ok {
			fmt.eprintln("Failed to checkout SHA to temporary build directory.")
			os.exit(1)
		}
		defer git.remove_worktree(parent_path, repo_data.name, tmp_build_dir)

		// run builder
		fmt.println("Running builder")
		binary, artifact_path, error := builder.build_package(
			ark_dir,
			tmp_build_dir,
			repo_data.name,
		)

		// run lock updater
		fmt.println("Updating lock")
		append(
			&lock_data.data,
			shared.Entry {
				name      = repo_data.name,
				version   = repo_data.spec,
				sha       = ref_sha,
				url       = repo_data.url,
				// TODO: add in the binary title from the builder
				binary    = "placeholder",
				timestamp = time.to_unix_seconds(time.now()),
				ref_kind  = ref_kind,
				ref_name  = ref_name,
			},
		)

		if !shared.write_lock(ark_dir, lock_data.data[:]) {
			fmt.println("ERROR: failed to write ark.lock")
			os.exit(1)
		}
		fmt.println("Running installer")
		// run installer
	}
}
