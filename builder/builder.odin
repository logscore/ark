package builder

import shared "../shared"

build_package :: proc(
	ark_dir: string,
	tmp_build_dir: string,
	package_name: string,
) -> (
	binary: string,
	artifact_path: string,
	error: string,
) {
	// Walk from base directory to ark_dir, falling back to autodetection. Return the array of shared.Packages
	build_recipes := walk_directories_for_ark_config(ark_dir)
	// iterate over and find the package whose name matched. Save in single variable. Stream it in?
	// If file isnt there, fallback to autodetection
	// if not in file, fallbakc to autodetection
	// If not present, fallback to autodetection. Prioritize optimized builds
	// If more than one build marker is detected (Cargo.tom and go.mod in same dir, error out and tell the user to config in ark.json)

	// find the tool from the build recipe on PATH
	// validate the version. Versions are exact.
	// If not there, error (THIS IS WHERE WE'D DO THE uv-LIKE TOOL CACHE)
	// Run the build. Run build in build_dir, apply the package.env, pip stdout and stderr to user
	// Validate result. join build dir with the project "out" and verify the artifact is a file
	// Return the build output file path for the installer package

	return "", "", ""
}

walk_directories_for_ark_config :: proc(ark_dir: string) -> shared.User_Config {
	// Check current working directory
	// Check ark dir
	// If none found, return
	return {}
}


// Step 1: find the build recipe. Use this order:
//   a. ark.json in the root of source_dir. The repository declares its own build.
//   b. ark.json in ark_dir. The user supplies or overrides the build.
//   c. autodetection from one marker file.
// Select the shared.Package whose `name` matches. Stop with an error and list the
// available names when no entry matches.
//
// Autodetection maps one marker file to one tool:
//   Cargo.toml    cargo build --release
//   go.mod        go build
//   build.zig     zig build
//   package.json  bun build
//   Makefile      make
// Two or more markers are ambiguous. Stop and tell the user to add ark.json. Do
// not guess a command, because a wrong command can write outside the checkout.
//
// Step 2: get the build tool. Use the resolution chain from the README:
//   1. Find the tool from the recipe in PATH.
//   2. Validate the version when `build.version` is set. Versions are exact.
//   3. When the tool is absent, stop with "x is not installed on the user PATH".
//      A later version downloads the tool to ~/.ark/tools/<tool>/<version>/ and
//      prepends that directory to PATH in memory only.
//
// Step 3: run the build. Set the working directory to source_dir. Apply
// `build.env` above the inherited environment. Send stdout and stderr to the
// user, because build output is the only progress that a long build gives.
// A non-zero exit code is a failure.
//
// Step 4: prove the result. Join source_dir and `out`. Assert that the path is
// a file. A build tool can exit 0 and write nothing, or write to a different
// path. Report the mismatch instead of a later confusing "binary not found".
//
// This package does not:
//   - move the artifact into ~/.ark/build      (installer)
//   - create or move the symlink in ~/.ark/bin (installer)
//   - write ark.lock                           (command layer)
//   - remove the worktree in ~/.ark/tmp        (command layer, on success and
//                                               on failure)
