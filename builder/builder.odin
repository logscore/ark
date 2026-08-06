package builder

// The builder makes a binary from a source checkout.
//
// This is the only stage that runs commands from the outside world. It must not
// change installed state. It reads the checkout, writes in the checkout, and
// reports where the artifact is. The installer moves the artifact after this.
//
// Input:
//   ark_dir     absolute path of ~/.ark
//   source_dir  temporary worktree from git.checkout_to_sha
//   name        package name that install parsed from the repository path
//
// Output:
//   binary         command name that the user calls. It is the base name of `out`.
//                  It can differ from `name`. The lock entry and the symlink use
//                  this value, not `name`.
//   artifact_path  absolute path of the built file in source_dir
//   error          one value for each failure below. Do not exit from this package.
//                  The command layer prints and exits.
//
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
