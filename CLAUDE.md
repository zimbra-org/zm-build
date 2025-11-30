# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is the Zimbra Collaboration Suite FOSS build system. The main entry point is `build.pl`, a Perl script that orchestrates cloning 59 git repositories, executing 60+ build stages, and producing RPM/DEB packages bundled into a `.tgz` installer.

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

### Build from config file
Create `config.build` with options, then run:
```bash
./build.pl
```

### Resume interrupted build
```bash
ENV_RESUME_FLAG=true ./build.pl [options]
```

### Checkout only (no build)
```bash
./build.pl --build-type=FOSS --stop-after-checkout
```

### Key Environment Variables
- `ENV_CACHE_CLEAR_FLAG=true` - Clear ~/.zcs-deps and ~/.ivy2/cache before build
- `ENV_RESUME_FLAG=true` - Resume from last incomplete build
- `ENV_GIT_UPDATE_INCLUDE=<pattern>` - Only update matching repos
- `ENV_SKIP_CLEAN_FLAG=1` - Skip 'clean' step
- `ENV_FORCE_REBUILD=<repos>` - Force rebuild specific repos

## Architecture

### Build Flow
1. **Initialization** - Parse options, detect OS platform via `rpmconf/Build/get_plat_tag.sh`
2. **Preparation** - Create cache dirs, download third-party JARs to ~/.zcs-deps
3. **Checkout** - Clone/update 59 repos defined in `instructions/FOSS_repo_list.pl`
4. **Build** - Execute 60+ stages from `instructions/FOSS_staging_list.pl` (ant, mvn, make)
5. **Package** - Create 12 packages using scripts in `instructions/bundling-scripts/`
6. **Bundle** - Create final .tgz installer

### Key Configuration Files
| File | Purpose |
|------|---------|
| `instructions/FOSS_remote_list.pl` | Git remote name to URL mappings |
| `instructions/FOSS_repo_list.pl` | 59 repositories to checkout with branch/tag info |
| `instructions/FOSS_staging_list.pl` | Build stages with dependencies and ant/mvn targets |
| `instructions/FOSS_package_list.pl` | 12 final packages to create |
| `config.build` | Runtime config (created from config.build.in template) |

### Output Structure
```
$HOME/BUILDS/<PLATFORM>-<RELEASE>-<VERSION>-<TIMESTAMP>_FOSS-<BUILD_NO>/
├── zm-build/zcs-*.tgz          # Main installer bundle
├── archives/zimbra-*/          # Individual packages
└── archive-access-*.txt        # Access instructions
```

### Package Bundling Scripts
Located in `instructions/bundling-scripts/`:
- `zcs-bundle.sh` - Creates the final .tgz installer
- `zimbra-core.sh`, `zimbra-store.sh`, etc. - Individual package scripts
- `utils.sh` - Shared utility functions

### RPM/DEB Specs
Located in `rpmconf/Spec/` - Use `@@VERSION@@` and `@@RELEASE@@` template variables

## Development Workflow (zm-mailbox example)

Build order for zm-mailbox subdirectories (dependencies flow upward):
1. `native`
2. `common`
3. `soap`
4. `client`
5. `store`

From each subdirectory:
```bash
ant -Dzimbra.buildinfo.version=8.7.6_GA clean compile publish-local deploy
```

`publish-local` adds artifacts to ~/.zcs-deps; `deploy` installs to runtime location.

## Supported Platforms

Detected automatically by `rpmconf/Build/get_plat_tag.sh`:
- Ubuntu: 12, 14, 16, 18, 20, 22, 24
- RHEL/CentOS/Rocky: 6, 7, 8, 9
- Debian: 7, 8, 9
- Platform tags: UBUNTU16_64, RHEL7_64, etc.

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
