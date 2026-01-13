# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!-- sample to copypaste
## [Unreleased]

### Added
- ...
### Fixed
- ...
### Changed
- ...
### Removed
- ...
-->

## [Unreleased]

### Added

- New release targets: `linux-aarch64` `linux-riscv64` `linux-x86_64` `linux-x86` 
  `windows-x86_64` `windows-x86`.
- Internal: `release` build step, for building official release targets. 
- Internal: `no-bin` build step, to `--watch` builds without emitting binaries.
- Internal: `no-run` build step, to `--watch` tests without running them.
- Internal: `asm` build step, for emitting assembly alongside binaries.

### Changed

- Improved error reporting for malformed command line input.
- Internal: Updated Zig version from `0.14.1` to `0.15.2`.
- Internal: Rewrote command line parser. Parser now implements an API.

### Fixed

- Cleaned up handling of some edge cases in command line parsing.
- Internal: Cleaned up ugly output from `clean` script.


## [1.0.0] - 2026-01-05

### Added

- Streaming formatter API.
- Disk IO support.
- Standard IO support.
- Cosmetic options for alignment and indentation in section-scoped contexts.
- Zig module export.


<!-- [unreleased]: https://github.com/everalert/x86fmt/compare/v1.0.0...HEAD -->
[unreleased]: https://github.com/everalert/x86fmt/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/everalert/x86fmt/releases/tag/v1.0.0
