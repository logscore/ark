package commands

import git "../git"
import help "../help"
import shared "../shared"

import "core:flags"
import "core:fmt"
import "core:os"

Update_Options :: struct {
	force:   bool `args: "name=force"`,
	version: string `args: "name=version"`,
}

update_package :: proc(ark_dir: string, options: []string) {
	if len(options) < 1 {
		fmt.println("Invalid usage:\n")
		help.print_help("update")
		os.exit(1)
	}

	package_name := options[0]
	if package_name == "--help" {
		help.print_help("update")
		os.exit(0)
	}

	arg_flags := options[1:]

	opts: Update_Options
	if len(arg_flags) != 0 {
		flags.parse(&opts, arg_flags, .Unix)
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
		if line.name == package_name {
			append(&installed, line)
		}
	}

	if len(installed) == 0 {
		fmt.printfln(`%s not installed, use 'ark install'`, package_name)
		os.exit(1)
	}

	want_version := opts.version
	if want_version == "" {
		want_version = "HEAD" // or resolve HEAD from remote
	}

	// NOTE: two repos publishing the same tool name isn't handled yet; install blocks that case for now
	ref_sha := git.resolve_repo_to_sha(
		ark_dir,
		shared.Repo{installed[0].repo, package_name, want_version},
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
		tmp_build_dir, checkout_ok := git.checkout_to_sha(ark_dir, ref_sha, package_name)
		if !checkout_ok {
			fmt.eprintln("Failed to checkout SHA to temporary build directory.")
			os.exit(1)
		}

		fmt.println("Running builder")
		fmt.println("Running installer")
		fmt.println("Updating lock")
		return
	}

	// Sha is in lock. Is the artifact on disk?
	active_version := shared.resolve_symlink_to_path(ark_dir, matched.binary)
	if active_version == "" {
		fmt.printfln(
			"Package '%[1]s' of version '%[2]s' is in lock file, but no binary can be found. Installing from lock file...",
			package_name,
			matched.version,
		)

		tmp_build_dir, checkout_ok := git.checkout_to_sha(ark_dir, ref_sha, package_name)
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
		fmt.printfln(
			"Package '%[1]s' of version '%[2]s' is already installed.\n\nPass --force to bypass this check or run 'ark use %[1]s <version>' to switch to your desired version.",
			package_name,
			matched.version,
		)
		os.exit(1)
	}

	tmp_build_dir, checkout_ok := git.checkout_to_sha(ark_dir, ref_sha, package_name)
	if !checkout_ok {
		fmt.eprintfln("Failed to checkout ref %s to temporary build directory.", ref_sha[:7])
		os.exit(1)
	}

	fmt.println("Running builder")
	fmt.println("Running installer")
	fmt.println("Updating lock")
}
