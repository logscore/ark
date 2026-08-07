package commands

import git "../git"
import shared "../shared"

import "core:flags"
import "core:fmt"
import "core:os"

Update_Options :: struct {
	package_name: string `args:"name=package,pos=0,required"`,
	force:        bool `args:"name=force"`,
	version:      string `args:"name=version"`,
}

update_package :: proc(ark_dir: string, options: []string) {
	git.ensure_git()

	opts: Update_Options
	err := flags.parse(&opts, options, .Unix)
	switch v in err {
	case flags.Help_Request:
		shared.print_help("update")
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

	lock_data, lock_ok := shared.read_lock(ark_dir)
	if !lock_ok {
		fmt.println("ERROR: failed to read ark.lock file")
		os.exit(1)
	}
	defer delete(lock_data.data)

	// filter lock data to only the name of the package requested
	installed := make([dynamic]shared.Entry)
	defer delete(installed)
	for line in lock_data.data {
		if line.name == opts.package_name {
			append(&installed, line)
		}
	}

	if len(installed) == 0 {
		fmt.printfln(`%s not installed, use 'ark install'`, opts.package_name)
		os.exit(1)
	}

	want_version := opts.version
	if want_version == "" {
		want_version = "HEAD" // or resolve HEAD from remote
	}

	// NOTE: two repos publishing the same tool name isn't handled yet; install blocks that case for now
	ref_sha := git.resolve_repo_to_sha(
		ark_dir,
		shared.Repo{installed[0].repo, opts.package_name, want_version},
	)

	// Is this sha already in the lock?
	matched: shared.Entry
	found: bool = false
	for e in installed {
		if e.sha == ref_sha {
			matched = e
			found = true
			break
		}
	}

	if !found {
		// New version, not yet in lock
		tmp_build_dir, checkout_ok := git.checkout_to_sha(
			ark_dir,
			ref_sha,
			opts.package_name,
			matched.repo,
		)
		if !checkout_ok {
			fmt.eprintln("Failed to checkout SHA to temporary build directory.")
			os.exit(1)
		}

		fmt.println("Running builder")
		fmt.println("Running installer")
		fmt.println("Updating lock")
		return
	}

	// Sha is in lock. Is the artifact of this exact version on disk?
	if !shared.artifact_exists(ark_dir, matched.name, matched.version, matched.binary) {
		fmt.printfln(
			"Package '%[0]s' of version '%[1]s' is in lock file, but no binary can be found. Installing from lock file...",
			opts.package_name,
			matched.version,
		)

		tmp_build_dir, checkout_ok := git.checkout_to_sha(
			ark_dir,
			ref_sha,
			opts.package_name,
			matched.repo,
		)
		if !checkout_ok {
			fmt.eprintfln("Failed to checkout ref %s to temporary build directory.", ref_sha[:7])
			os.exit(1)
		}

		fmt.println("Running builder")
		fmt.println("Running installer")
		fmt.println("Updating lock")
		return
	}

	if !opts.force {
		// The version is on disk. Activate it, or report that it is active.
		if shared.is_active_version(ark_dir, matched.name, matched.version, matched.binary) {
			fmt.printfln(
				"Package '%[0]s' of version '%[1]s' is already installed and active.\n\nPass --force to rebuild it.",
				opts.package_name,
				matched.version,
			)
			os.exit(1)
		}

		target := shared.artifact_path(ark_dir, matched.name, matched.version, matched.binary)
		defer delete(target)

		if relink_err := shared.relink_binary_atomic(ark_dir, matched.binary, target);
		   relink_err != nil {
			os.exit(1)
		}

		fmt.printfln(
			"Package '%[0]s' of version '%[1]s' is installed. It is now active.",
			opts.package_name,
			matched.version,
		)
		return
	}

	tmp_build_dir, checkout_ok := git.checkout_to_sha(
		ark_dir,
		ref_sha,
		opts.package_name,
		matched.repo,
	)
	if !checkout_ok {
		fmt.eprintfln("Failed to checkout ref %s to temporary build directory.", ref_sha[:7])
		os.exit(1)
	}

	fmt.println("Running builder")
	fmt.println("Running installer")
	fmt.println("Updating lock")
}
