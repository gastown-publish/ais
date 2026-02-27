# Contributing to ais

Thanks for your interest in contributing! Here's how to get started.

## Getting Started

1. Fork and clone the repo
2. Create a branch for your work
3. Make your changes
4. Submit a pull request

## Development Setup

```bash
git clone https://github.com/<you>/ais.git
cd ais

# Make sure the tools work
./bin/ais --help
./bin/kimi-account --help
```

## Code Standards

- **Shell scripts must pass shellcheck** — run `shellcheck bin/* scripts/*` before submitting
- Keep bash 4.0+ compatibility
- Use the existing code style (2-space indent, `die`/`warn`/`info` helpers)
- Test against both Claude and Kimi agent types when possible

## Finding Work

This project uses [beads](https://github.com/gastown-publish/beads) for issue tracking:

```bash
bd ready          # Show unblocked issues
bd show <id>      # View issue details
```

Look for issues labeled as good first contributions, or open a new issue to discuss what you'd like to work on.

## Pull Request Process

1. Keep PRs focused — one feature or fix per PR
2. Update documentation if you change CLI behavior
3. Ensure `shellcheck` passes with no warnings
4. Describe what your change does and why in the PR description

## Reporting Bugs

Open a beads issue or GitHub issue with:
- What you expected to happen
- What actually happened
- Your environment (OS, bash version, tmux version)
- Steps to reproduce

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
