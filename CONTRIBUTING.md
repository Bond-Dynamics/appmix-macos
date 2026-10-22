# Contributing to AppMix

Thanks for your interest. AppMix is a small per-app audio mixer for macOS, maintained by Bond Dynamics. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug or asking for a feature

Open an [issue](https://github.com/Bond-Dynamics/appmix-macos/issues/new/choose) using one of the templates. For bugs, the output of `swift run appmix list` saves a lot of back-and-forth. It shows which apps and output devices AppMix can see.

**Security problems should not go in a public issue.** See [SECURITY.md](SECURITY.md).

## Building and testing

You need macOS 15 or later and Xcode 16 or later (Swift 6).

```bash
swift build
swift test
```

To run the menu bar app as a real app bundle:

```bash
scripts/make-app.sh && open dist/AppMix.app
```

AppMix uses Core Audio process taps, which need audio-recording permission. macOS asks on behalf of the app that launched the process. If routing produces silence, allow AppMix (or your terminal, for the `appmix` CLI) under **System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only**.

The `appmix` CLI is the fastest way to test routing without the UI:

```bash
swift run appmix list
swift run appmix route --app spotify --to "MacBook Pro Speakers" --volume 40 --meter
```

## Making a change

1. Fork the repository and create a branch from `main`.
2. Make the change, with tests for anything in `Sources/MixerCore`. Tests use Swift Testing (`import Testing`).
3. Make sure `swift build` has no warnings and `swift test` passes.
4. Commit using [Conventional Commits](https://www.conventionalcommits.org/): `feat: …`, `fix: …`, `docs: …`, `test: …`, `chore: …`.
5. Open a pull request against `main` and fill in the template.

## How pull requests are merged

- CI (`CI Success`) must pass. For contributors outside the project, a maintainer approves the CI run first.
- A maintainer reviews and approves the PR, and every review conversation is resolved.
- PRs land as **merge commits**, so your branch's history is kept as you wrote it. Tidy it up on your branch before asking for review if you want a cleaner history.
- Releases are cut by maintainers from the `release` branch, so you never need to touch `release`, `VERSION` or tags.

## Code style

Match the code around your change. That means small focused files, readable names, and errors handled rather than swallowed. Code that runs on the real-time audio thread (inside an IOProc) must not allocate, lock or log.

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
