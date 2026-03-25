# Contributing to KAGI

Thanks for your interest in contributing!

## How to Contribute

1. **Fork** the repository
2. **Create a branch** from `main` (`git checkout -b feature/your-feature`)
3. **Make your changes** following the guidelines below
4. **Test** your changes (`xcodebuild test` for iOS, `cargo test` for server)
5. **Submit a PR** with a clear description of the change

## Guidelines

- Follow existing code style and naming conventions
- Keep PRs focused — one feature or fix per PR
- Write tests for new functionality
- Update documentation if behavior changes
- iOS code uses SwiftUI + SwiftData patterns already in the codebase
- Server code follows axum + rusqlite patterns in `server/`

## Development Setup

### iOS

```bash
cd ios
xcodegen generate
open Kacha.xcodeproj
```

### Server

```bash
cd server
cargo run
```

## Reporting Issues

Open a GitHub issue with:
- Steps to reproduce
- Expected vs actual behavior
- iOS version / device (if applicable)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
