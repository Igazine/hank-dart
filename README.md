# HAL for Dart

A Dart implementation of the Hybrid Automation Language (HAL).

This repository provides a spec-compliant, environment-agnostic library for embedding the HAL interpreter into any Dart or Flutter application.

## Features
- **Environment Agnostic**: The core library has zero dependencies on `dart:io` or Flutter.
- **Spec-Compliant Runner**: Implements recursive `@macro` pre-processing, AST caching, and host argument injection.
- **Modular StdLib**: Full parity with HAL 1.0 standard library specifications.
- **Mobile-Ready**: Perfectly suited for embedding in Flutter apps for dynamic logic.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  hal:
    git:
      url: https://github.com/Igazine/hal-dart.git
```

## Example Demo

An example CLI demo is included in `example/demo`. To run the conformance tests:

1. **Initialize Submodules**:
   ```bash
   git submodule update --init --recursive
   ```
2. **Run Demo**:
   ```bash
   cd example/demo
   dart pub get
   dart run bin/main.dart
   ```

## Project Links

- **HAL Core Repo**: [Igazine/hal](https://github.com/Igazine/hal)
- **Official Documentation**: [https://igazine.github.io/hal/](https://igazine.github.io/hal/)

## License

This project is licensed under the MIT License.
