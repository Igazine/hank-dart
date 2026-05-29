# Hank for Dart

Hank is a purely symbolic, instruction-oriented embeddable language designed to bring secure, dynamic automation to any host application. Built on a strict air-gapped execution model, Hank has zero built-in I/O, guaranteeing that scripts cannot access the filesystem, network, or OS without explicit delegation. This makes it the perfect predictable environment for game scripting, microservice orchestration, and user-facing plugin systems. With a highly readable, keyword-less syntax and universal cross-platform parity, Hank seamlessly bridges the gap between static configuration files and complex general-purpose programming.

This repository provides the official Dart implementation of the Hank language. It is a spec-compliant, environment-agnostic library for embedding the Hank interpreter into any Dart or Flutter application.

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
