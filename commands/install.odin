package commands

import "core:flags"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:time"

import git "../git"
import help "../help"
import shared "../shared"

Install_Options :: struct {
	repo_url: string `args:"name=git_url,pos=0,required"`,
	version:  string `args:"name=version"`,
	force:    bool `args:"name=force"`,
}

install_package :: proc(ark_dir: string, options: []string) {
	opts: Install_Options
	err := flags.parse(&opts, options, .Unix)
	switch v in err {
	case flags.Help_Request:
		help.print_help("install")
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
		url  = "",
		name = "",
		spec = "",
	}

	// If the version is not given, we want to update to the most up to date version, starting with tag, then branch/sha
	// TODO: we cannot store HEAD as the version as that breaks the lock rule that we cannot have two packages of the same version in the lock. We can store the most recent sha, or most recent tag
	if opts.version == "" {
		repo_data.spec = "HEAD"
	} else {
		repo_data.spec = opts.version
	}

	// parse url.
	// TODO: eventually support bare github.com/user/tool or user/tool
	scheme, host, full_path, _, _ := net.split_url(opts.repo_url)

	base_path := strings.split(full_path, "@")[0]
	if scheme == "" && strings.starts_with(host, "git@") {
		repo_data.url = strings.concatenate({host, strings.split(full_path, "@")[0]})
	} else if scheme == "https" {
		repo_data.url = strings.concatenate({scheme, "://", host, base_path})
	} else {
		fmt.printfln("Invalid repo url: %s\n", opts.repo_url)
		os.exit(1)
	}

	base := strings.trim_suffix(base_path, ".git")
	path_tokens := strings.split(base, "/")
	repo_data.name = path_tokens[len(path_tokens) - 1]

	lock_data, lock_ok := shared.read_lock(ark_dir)
	if !lock_ok {
		os.exit(1)
	}

	// Process out to git, clone to .ark/cache, fetch refs, find desired ref, return ref sha
	ref_sha := git.resolve_repo_to_sha(ark_dir, repo_data)

	if repo_data.spec == "HEAD" {
		repo_data.spec = ref_sha[:7]
	}

	installed_index: int
	installed := make([dynamic]shared.Entry)
	for line, index in lock_data.data {
		if line.name == repo_data.name && line.sha == ref_sha {
			installed_index = index
			append(&installed, line)
		}
	}
	defer delete(installed)

	// Is sha in lock?
	if len(installed) == 1 {
		// Is artifact on disk?
		resolved_active_linked_file := shared.resolve_symlink_to_path(ark_dir, installed[0].binary)
		if resolved_active_linked_file != "" {
			// Is --force true?
			if opts.force {
				// pull build and install
				tmp_build_dir, checkout_ok := git.checkout_to_sha(ark_dir, ref_sha, repo_data.name)
				if !checkout_ok {
					fmt.eprintln(
						"Failed to checkout ref %s to temporary build directory.",
						ref_sha[:7],
					)
					os.exit(1)
				}

				// run builder
				fmt.println("Running builder")
				// run installer
				fmt.println("Running installer")
				// run lock updater
				fmt.println("Updating lock")
				// Force build means we replace the lock entry.
				// ? Is there a more efficient way to do this instead of shadowing the data index Entry??
				// TODO: double check that these values are accurate as the builder may pull in new install instruction from the user config, and things like the binary name might be different
				lock_data.data[installed_index] = shared.Entry {
					lock_data.data[installed_index].name,
					lock_data.data[installed_index].version,
					lock_data.data[installed_index].sha,
					lock_data.data[installed_index].repo,
					// TODO: add in the binary title from the builder
					lock_data.data[installed_index].binary,
					time.to_unix_seconds(time.now()),
				}

				if !shared.write_lock(ark_dir, lock_data.data[:]) {
					fmt.println("ERROR: failed to write ark.lock")
					os.exit(1)
				}
			} else {
				// tell the user its installed and to switch with ark use
				fmt.printfln(
					"Package '%[1]s' of version '%[2]s' is already installed.\n\nPass --force to bypass this check or run 'ark use %[1]s <version>' to switch to your desired version.",
					repo_data.name,
					opts.version,
				)
				os.exit(1)
			}
			// Is artifact not on disk?
		} else {
			// warn the user, and build, and install anyways
			fmt.printfln(
				"Package '%[0]s' of version '%[1]s' is in lock file, but no binary can be found. Installing package from lock file...\n",
				repo_data.name,
				installed[0].version,
			)

			tmp_build_dir, checkout_ok := git.checkout_to_sha(ark_dir, ref_sha, repo_data.name)
			if !checkout_ok {
				fmt.eprintln(
					"Failed to checkout ref %s to temporary build directory.",
					ref_sha[:7],
				)
				os.exit(1)
			}

			// run builder
			fmt.println("Running builder")
			// run installer
			fmt.println("Running installer")
			// run lock updater
			fmt.println("Updating lock")
			// Like with --force, we overwrite the value with the new installed timestamp
			// TODO: double check that these values are accurate as the builder may pull in new install instruction from the user config, and things like the binary name might be different
			lock_data.data[installed_index] = shared.Entry {
				lock_data.data[installed_index].name,
				lock_data.data[installed_index].version,
				lock_data.data[installed_index].sha,
				lock_data.data[installed_index].repo,
				// TODO: add in the binary title from the builder
				lock_data.data[installed_index].binary,
				time.to_unix_seconds(time.now()),
			}

			if !shared.write_lock(ark_dir, lock_data.data[:]) {
				fmt.println("ERROR: failed to write ark.lock")
				os.exit(1)
			}
		}
	} else { 	// Sha is not in lock. New version
		// checkout to spec, build, append lock file, install
		tmp_build_dir, checkout_ok := git.checkout_to_sha(ark_dir, ref_sha, repo_data.name)
		if !checkout_ok {
			fmt.eprintln("Failed to checkout SHA to temporary build directory.")
			os.exit(1)
		}

		// run builder
		fmt.println("Running builder")
		// run installer
		fmt.println("Running installer")
		// run lock updater
		fmt.println("Updating lock")

		append(
			&lock_data.data,
			shared.Entry {
				repo_data.name,
				repo_data.spec,
				ref_sha,
				repo_data.url,
				// TODO: add in the binary title from the builder
				repo_data.name,
				time.to_unix_seconds(time.now()),
			},
		)

		if !shared.write_lock(ark_dir, lock_data.data[:]) {
			fmt.println("ERROR: failed to write ark.lock")
			os.exit(1)
		}
	}
}
