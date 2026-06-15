# MDSPACE external dependency build CI

Minimal cross-platform CI scaffold for compiling the MDSPACE external command-line dependencies from source.

Included dependencies:

- ElNemo (`MDSPACE-toolkit/nma`, `master`)
- GENESIS (`MDSPACE-toolkit/mdspace-genesis`, `2.1.6.2`)
- SMOG2 (`2.5`)
- XMIPP (`I2PC/xmipp3`, `v3.25.06.0-Rhea`)

Excluded deliberately:

- VTK: use a system/package-manager VTK build with the required Qt 6 modules.
- RTB2: it can be adapted from the ElNemo build separately.

## Workflows

- `macOS build`: builds the selected dependency natively on `macos-14`.
- `Windows build`: builds the selected dependency in a native MSYS2/MinGW64 environment on `windows-2025`.

Both workflows use a component matrix. This makes failures independent and shows immediately which dependency needs a platform-specific patch.

## Important status

This repository is a **test harness**, not a claim that all four upstream projects already compile unchanged on macOS and Windows.

ElNemo and GENESIS contain substantial Fortran code. XMIPP has a secondary source-fetch step and was primarily designed for Unix-like environments. The Windows workflow is intentionally strict: a component that cannot compile natively fails its own matrix job rather than being silently skipped.

## Local use

macOS:

```bash
./scripts/build-macos.sh elnemo
./scripts/build-macos.sh genesis
./scripts/build-macos.sh smog2
./scripts/build-macos.sh xmipp
```

MSYS2 MinGW64:

```bash
./scripts/build-windows-msys2.sh elnemo
./scripts/build-windows-msys2.sh genesis
./scripts/build-windows-msys2.sh smog2
./scripts/build-windows-msys2.sh xmipp
```

The default installation prefix is `$PWD/install/<component>`. Override it with `PREFIX=/path/to/prefix`.

## Suggested first run

Trigger each workflow manually with `workflow_dispatch`, beginning with ElNemo. Once the exact upstream failures are known, keep platform patches in `patches/<component>/` and apply them from the corresponding build function.
