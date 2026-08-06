package installer

// The installer makes a built binary usable. It owns ~/.ark/build and
// ~/.ark/bin. It does not build, and it does not use git.
//
// The stage has two procedures, because the command layer must write ark.lock
// between them. The lock records intent. The symlink holds the live state.
// Write the artifact, then the lock, then the symlink:
//   - A failure after the lock write leaves the version installed but not
//     active. `ark use <name> <version>` repairs that state.
//   - The opposite order can leave an active binary that no lock entry
//     describes, and `ark list` and `ark uninstall` cannot see it.
//
// Procedure 1: place the artifact.
//   Input:  ark_dir, name, version, binary, artifact_path
//   Output: installed_path, error
//
//   1. Make build/<name>/<version>/.
//   2. Copy artifact_path to build/<name>/<version>/<binary>.tmp, then rename
//      the copy to build/<name>/<version>/<binary>. Copy, because the worktree
//      in ~/.ark/tmp and the build directory can be on different file systems.
//      Rename in one directory is atomic, so a reader never sees a part of a
//      file.
//   3. Set the executable bit.
//   4. Remove the temporary file when a step fails. Do not leave the build
//      directory in a half state.
//   5. Return the destination path.
//
//   The path shape must stay the same as commands/use.odin, which builds
//   {ark_dir}/build/{name}/{version}/{binary} to switch versions. The two
//   paths must agree, or `ark use` cannot find a version that install wrote.
//
// Procedure 2: activate the version.
//   Input:  ark_dir, binary, installed_path
//   Output: error
//
//   Point bin/<binary> at installed_path with shared.relink_binary_atomic. That
//   helper writes a temporary link and renames it, so the command name never
//   disappears from PATH. The same call creates the first link and replaces an
//   existing link.
//
//   Install activates the version that it installed, like cargo, go, and brew.
//   Every install path that makes an artifact must call this:
//     - a new version, because no link exists and the tool is not on PATH
//     - a recovery install, because the link is absent or points to a file
//       that is deleted
//     - a --force rebuild, because the builder can report a different binary
//       name than the lock entry holds
//   An install that finds the same sha and gets no --force does not build, so
//   it does not activate. It tells the user to run `ark use`.
//
//   Report a failure here as "installed but not active", and name the `ark use`
//   command that completes the install.
//
// This package does not:
//   - remove versions or symlinks (commands/uninstall.odin)
//   - write or read ark.lock      (command layer, with shared.write_lock)
//   - remove ~/.ark/tmp worktrees (command layer)
