# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.03] - 2025-12-29

### Added
- Linux (amd64/arm64) prebuilt tarballs and installer support.
- Installer PATH hint for Linux when installing outside `/usr/local/bin`.

## [0.1.0] - 2025-12-29

### Added
- First public OSS release of FounderBooster (fb).
- Auto mode (Docker-first) bootstrap for existing local apps.
- Manual mode (port-first) bootstrap for known ports.
- Cloudflare tunnel creation/reuse, DNS record management, and SSL via Cloudflare.
- Local state isolation per app/env.
- Optional Early Access convenience: prebuilt binaries, one-line installer, and `fb self update`.

### Notes
- FounderBooster is a CLI control plane, not a hosting provider.
- Core functionality is fully open source and usable without a license.
