# Hank for Dart

A Dart implementation of the Hank language.

This repository provides a spec-compliant, environment-agnostic library for embedding the Hank interpreter into any Dart or Flutter application.

## Features
- **Environment Agnostic**: The core library has zero dependencies on `dart:io` or Flutter.
- **Spec-Compliant Runner**: Implements recursive `@macro` pre-processing, AST caching, and host argument injection.
- **Modular StdLib**: Full parity with official standard library specifications.
- **Mobile-Ready**: Perfectly suited for embedding in Flutter apps for dynamic logic.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  hank:
    git:
      url: https://github.com/Igazine/hank-dart.git
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

- **Hank Core Repo**: [Igazine/hank](https://github.com/Igazine/hank)
- **Official Documentation**: [https://igazine.github.io/hank/](https://igazine.github.io/hank/)

## License

This project is licensed under the MIT License.
