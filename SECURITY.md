# Security Policy

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Report it privately through GitHub's private vulnerability reporting:
**[Report a vulnerability](https://github.com/Bond-Dynamics/appmix-macos/security/advisories/new)**.
The report is visible only to the maintainers until a fix is published.

Please include:

- what the problem is and what an attacker could do with it
- steps to reproduce, or a proof of concept
- the AppMix version (from the release you installed, or the commit) and your macOS version

This is a small project maintained on a best-effort basis. We will acknowledge your report, keep you updated while we work on it, and credit you in the advisory unless you prefer not to be named.

## Supported versions

Only the latest release on the [Releases page](https://github.com/Bond-Dynamics/appmix-macos/releases) receives security fixes.

## Scope

AppMix runs entirely on your Mac. It has no network code, no accounts and no telemetry. Things that are in scope include:

- AppMix capturing or routing audio from an app the user did not choose
- anything that lets another process misuse AppMix's audio-recording permission
- problems with the signed and notarized release artifacts, or the workflows that build them
