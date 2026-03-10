# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is the Zimbra Collaboration Suite FOSS build system. The main entry point is `build.pl`, a Perl script that orchestrates cloning 59 git repositories, executing 90+ build stages, and producing RPM/DEB packages bundled into a `.tgz` installer.

## Build Commands

### Full Build (version 10.1.0 example)
```bash
ENV_CACHE_CLEAR_FLAG=true ./build.pl \
  --ant-options -DskipTests=true \
  --git-default-tag=10.1.0 \
  --build-release-no=10.1.0 \
  --build-type=FOSS \
  --build-release=LIBERTY \
  --build-release-candidate=GA \
  --build-thirdparty-server=files.zimbra.com \
  --no-interactive
```

### Patch Build (multiple tag fallback)
Tags are tried in CSV order until one matches each repo:
```bash
--git-default-tag=10.0.8,10.0.7,10.0.6,10.0.5,10.0.4,10.0.3,10.0.2,10.0.1,10.0.0-GA
```

### Build from config file
Create `config.build` with options (format: `KEY = VALUE` or `%KEY = subkey=value` for hashes), then run `./build.pl`. See `config.build.in` for template.

### Resume interrupted build
```bash
ENV_RESUME_FLAG=true ./build.pl [options]
```
Uses `.build.last_no_ts` for BUILD_NO/BUILD_TS and `.built.{TIMESTAMP}` markers to skip completed stages.

### Checkout only (no build)
```bash
./build.pl --build-type=FOSS --stop-after-checkout
```

### Key Environment Variables
- `ENV_CACHE_CLEAR_FLAG=true` - Clear ~/.zcs-deps and ~/.ivy2/cache before build
- `ENV_RESUME_FLAG=true` - Resume from last incomplete build
- `ENV_GIT_UPDATE_INCLUDE=<pattern>` - Only update repos matching comma-separated regex patterns
- `ENV_SKIP_CLEAN_FLAG=1` - Skip 'clean' step in build stages
- `ENV_FORCE_REBUILD=<repos>` - Force rebuild specific repos (ignore .built markers)
- `ENV_BUILD_INCLUDE=<pattern>` - Only build stages matching comma-separated regex patterns
- `ENV_PACKAGE_INCLUDE=<pattern>` - Only package matching comma-separated regex patterns
- `ENV_GIT_FULL_CLONE=<pattern>` - Full clone (no --depth=1) for matching repos

## Architecture

### Build Flow (`build.pl` main phases)
1. **InitGlobalBuildVars()** - Parse options (3-tier: CLI → `config.build` → `.build.last_no_ts` → defaults), detect OS via `get_plat_tag.sh`, validate prerequisites (cc, java, mvn, ant, ruby, make)
2. **Prepare()** - Create cache dirs, download third-party JARs to `~/.zcs-deps`, write version info to `RE/` files
3. **Checkout()** - Clone/update repos from `FOSS_repo_list.pl` using remotes from `FOSS_remote_list.pl`. Shallow clones by default (except zm-mailbox). Git tag/branch fallback: tries CSV list in order.
4. **Build()** - Execute stages from `FOSS_staging_list.pl`. Per stage: clean → ant/mvn/make (tool_seq fallback chain) → optional `stage_cmd` (Perl anonymous sub) → rsync to package dirs. Then runs bundling scripts for each package in `FOSS_package_list.pl`.
5. **Deploy()** - Create RPM/DEB repository metadata (createrepo / dpkg-scanpackages), generate archive access instructions, optional nginx config for LOCAL_DEPLOY.

### Key Configuration Files
| File | Purpose |
|------|---------|
| `instructions/FOSS_remote_list.pl` | Git remote name → URL mappings (gh-zm=GitHub/Zimbra, gh-ks=GitHub/kohlschutter) |
| `instructions/FOSS_repo_list.pl` | 59 repos: `{name, tag, remote, repo_name_suffix}` |
| `instructions/FOSS_staging_list.pl` | 90+ build stages: `{dir, ant_targets, mvn_targets, make_targets, stage_cmd, deploy_pkg_into, partial}` |
| `instructions/FOSS_package_list.pl` | 11 packages + zcs-bundle |
| `config.build` / `config.build.in` | Runtime config with `KEY = VALUE` and `%KEY = subkey=value` format |

### Staging List Patterns
- **`deploy_pkg_into`** routes artifacts: `"bundle"` → final .tgz, or package name → specific package dir
- **`stage_cmd`** is a Perl anonymous sub receiving `($CFG, \&SysExec)` for non-standard build steps (e.g., rsync, SQL file copying)
- **`partial`** flag marks stages that don't require all build tools
- **`tool_seq`** defaults to `["ant", "mvn", "make"]` — only runs tools with defined targets

### Package Bundling Scripts
Located in `instructions/bundling-scripts/`:
- `utils.sh` - Shared utilities: `Copy()`, `Cpy2()`, `CreatePackage()` (dispatches to Debian/RHEL)
- `zcs-bundle.sh` - Creates the final .tgz installer with bin/, data/, docs/, lib/jars/, packages/
- `zimbra-core.sh` (675 lines, largest) - Complex file permission matrix, NETWORK vs FOSS variants
- `zimbra-store.sh`, `zimbra-ldap.sh`, etc. - Individual package scripts following same pattern

Each script: source utils.sh → define CreateDebianPackage()/CreateRhelPackage() → call CreatePackage()

### RPM/DEB Specs
Located in `rpmconf/Spec/` - Use `@@VERSION@@` and `@@RELEASE@@` template variables. Pre-built packages (no %prep, %build, %install sections).

### Platform Detection
`rpmconf/Build/get_plat_tag.sh` returns tags like UBUNTU16_64, RHEL7_64, etc. Maps CentOS/Rocky/Scientific/Fedora → RHEL equivalents.

### Output Structure
```
$HOME/BUILDS/<PLATFORM>-<RELEASE>-<VERSION>-<TIMESTAMP>_FOSS-<BUILD_NO>/
├── zm-build/zcs-*.tgz          # Main installer bundle
├── archives/zimbra-*/          # Individual packages
└── archive-access-*.txt        # Access instructions
```

### Build State Persistence
- `.build.last_no_ts` stores BUILD_NO and BUILD_TS for resume
- `.built.{TIMESTAMP}` marker files prevent re-building completed stages
- `RE/BUILD`, `RE/MAJOR`, `RE/MINOR`, `RE/MICRO` hold version components

### Key Utility Functions in build.pl
- `SysExec()` - Command execution with color-coded output (green=command, blue=headers, red=errors)
- `Clone()` - Git clone/pull with tag/branch fallback and shallow clone support
- `LoadProperties()` - Property file parser supporting both scalar and hash notation
- `RunInDir()` - Fork-based execution in a different directory
- `Die()` - Error handler with stack trace

## CI/CD

CircleCI v2.0 config in `.circleci/config.yml`:
1. **checkout** job: clone + `--stop-after-checkout` on Ubuntu 16.04
2. **build_XXX** jobs: parallel builds on Ubuntu 16/14/12 + CentOS 6 using `ENV_GIT_UPDATE_INCLUDE=@` (skip git updates)
3. **deploy_s3**: manual approval gate → S3 sync
4. **deploy_ec2**: manual approval gate → SSH deploy via `.circleci/jobs/deploy_ec2/deploy.sh`

Filters: master and develop branches only.

## Development Workflow (zm-mailbox example)

Build order for zm-mailbox subdirectories (dependencies via ivy.xml):
1. `native` → 2. `common` → 3. `soap` → 4. `client` → 5. `store`

From each subdirectory:
```bash
ant -Dzimbra.buildinfo.version=8.7.6_GA clean compile publish-local deploy
```

`publish-local` adds artifacts to `~/.zcs-deps`; `deploy` installs to runtime location and restarts services.

## GIT_OVERRIDES

Override per-repo git settings via `config.build` or CLI:
```
%GIT_OVERRIDES = zm-mailbox.branch=dev
%GIT_OVERRIDES = zm-mailbox.tag=10.1.0
%GIT_OVERRIDES = myremote.url-prefix=ssh://git@github.com
```

## Dependencies

**Ubuntu:**
```bash
sudo apt-get install software-properties-common openjdk-8-jdk ant ant-optional ant-contrib ruby git maven build-essential debhelper
```

**CentOS 7:**
```bash
sudo yum groupinstall 'Development Tools'
sudo yum install java-1.8.0-openjdk ant ant-junit ruby git maven cpan wget perl-IPC-Cmd
```

**Docker (recommended):**
```bash
docker run -it zimbra/zm-base-os:devcore-ubuntu-16.04 bash
```
