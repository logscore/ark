# Ark

git based platform agnostic package manager

## Lock file

It is a unix style file with one tool per line. we can have multiple versions by denoting the active one b resolving the symlink

```text
# name version commit source bin installed_timestamp
mytool v1.2.3 a1b2c3d github.com/user/mytool mytool 123456
mytool v1.2.2 e5f6g7h github.com/user/mytool mytool 123567
rg 14.1.0 f1a2b3c github.com/BurntSushi/ripgrep rg 124567
```

## the .ark dir

```text
.ark/
  build/
    <tool> # clean build artifacts divided by version
      <sha7>/
        tool
      <sha7>/
        tool
    rg
      v14.5.6/
        rg
  repos/
    <host>/
      <path_to>
        <repo_name>.git # Dirty, holds the git clones, refs and tags

  bin/ # symlinks to build/ dir binaries
    rg
    tool
    odin
  tmp/ # temporary build directory
    build-<first_10_chars_of_commit_sha>/
    build-<first_10_chars_of_commit_sha>/
    build-<first_10_chars_of_commit_sha>/
  ark.lock # The lock file (see above for details)
  ark.json # Global config file (optional)
```

## commands

- install <repo_url> [--version <version>] [--force]: pulls, builds and installs the tool based on the repo_url. Force ignores the hash comparison block and pulls, rebuilds and reinstalls.
- uninstall <tool> [--version <version>]: uinstalls the tool. version is optional. Without it, we uninstall all instances of the tool. Might add a warning and --force command to the multi instance uninsnstall.
- update <tool> --version <tagged_version> --force: updates the tool to hte most recent version. --version specifies the version to udate to (can be a lower version too. --force updates even if the version is already installed. Note on the lock file <> disk relationship when updating a package. Lock is the install(ed) intent. It tells us what the user wants on the system. The disk is the cache. Lock hit + disk cache miss is rebuildable. So we rebuild from that lock repo + sha.
- list <tool> [--version <version>]: lists all the tools, displaying the active one with "* active" along side thier paths and repo source + commit sha. Version is optional and will only display that version.
- use <tool> [--version <version>]: sets active tool to that version. Will eventually add a rollback command which holds a kv of previously set versions in /tmp/ark so you can run ark rollback <tool> and itll rollback instantly to hte previous version
- build <path_to_project> --with <whatever_build_command> --no-cache-tools: autodetects the projects tooling and builds with defined build script. --with overrides the autodetection and tries to run the build with that command. --no-cache-tools writes tool to .ark/tools/<tool>/<version> and deletes when build finishes. Its for CI pipelines (not in MVP).

## build tools

support go, rust, zig, bun, make

We just use whatever is on the system and throw a "x isnt installed on the users path. Please install it" error if not there.

Eventually we will have a tool cache like uvx.

build tool resolution chain:

1. read tool from ark.toml (local or repo)
2. check tool exists in PATH. Validate the version
3. if not exists, check the .ark/tools dir for the tool. If doesnt exist, download release binary to ~/.ark/tools/<tool>/<version>/
4. prepend add path to binary to command PATH. It sits only in memory and is discarded when build finishes. Binaries are big, so we keep them in the tools dir, we just hide that from the user.
5. Versions are exact. rust@1.81 means 1.81.0, not latest 1.81. We require the user to specify the version. Later we can add a latest resolve flow.
6. Run installs in parallel. Show "provisioning xyz..." on first install

## the ark.json file

It has one job. How do i build this repo into a binary and where do i stick the binary?

```json
{
  "$schema": "https://lsreeder.com/ark/schema.json", // or local path
  "packages": [
    {
      "name": "mypackage",
      "build": {
        "build_tool": "cargo",
        "version": "1.81.0",
        "args": ["build", "--release"],
        "env": {
          "FEATURE": "production"
        }
      },
      // Note that the name of the binary file will be what is used in the terminal. "name" is what the user uses to manage the package.
      "out": "target/release/pkg"
    }
  ]
}
```
