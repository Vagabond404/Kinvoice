---
name: anti-slop
description: Enforce zero placeholder code, zero dummy implementations, and production-grade Dart/Flutter syntax with complete error handling.
---

# Anti-Slop: Production Quality & Zero-Placeholder Standard

## Overview
This skill guarantees that all code generated for the Kinvoice platform meets strict production engineering standards. AI code generation often suffers from "slop": placeholder comments, empty stubs, mock data masked as production logic, swallowed errors, and loose typing. This skill enforces zero-tolerance for slop.

---

## 1. Zero-Placeholder Policy (Hard Gate)

- **No TODOs / Stubs:** Never output `// TODO: implement`, `throw UnimplementedError()`, or empty function bodies (`{}`). Every declared method must be fully implemented.
- **No Pseudo-Implementations:** Never use fake delays (`await Future.delayed(...)`) to simulate backend/native operations when actual logic is requested.
- **No Truncated Code:** Never omit sections of code with comments like `// ... rest of code unchanged ...` inside newly written or refactored components unless specifically performing targeted diffs.
- **Complete Edge-Case Handling:** Never leave switch statements without exhaustive coverage or fallthrough without explicit assertions.

---

## 2. Production-Grade Dart Standards

- **Strict Typing:**
  - Avoid `dynamic` and raw `Object?` unless dealing with arbitrary JSON deserialization or inter-isolate message envelopes.
  - Specify exact generic types for collections: `final List<InvoiceItem> items = [];` instead of `var items = [];`.
  - Always enable sound null safety with explicit nullability contracts (`String?` vs `String`).
- **Immutability & Const Correctness:**
  - Mark immutable classes with `@immutable`.
  - Prefer immutable data structures and `final` fields.
  - Use `const` constructors wherever possible to optimize Flutter widget rebuild trees.
- **Resource Management & Lifecycle:**
  - Always dispose `StreamController`, `ChangeNotifier`, `AnimationController`, `TextEditingController`, and FFI allocations in the widget or service `dispose()` / `close()` lifecycle.
  - Cancel all `StreamSubscription` instances to prevent background memory leaks.

---

## 3. Robust Error & Exception Handling

- **No Swallowed Exceptions:** Never write `catch (e) {}` without logging or propagating.
- **Typed Exceptions:** Define domain-specific exceptions (e.g., `AudioCaptureException`, `InferenceException`, `StorageException`) rather than throwing generic strings or `Exception(msg)`.
- **Structured Error Propagation:** Use `Result<T, E>` patterns or well-defined asynchronous streams to surface recoverable errors to the UI layer cleanly.

---

## 4. Pre-Delivery Quality Checklist

Before completing any task, verify:
1. Does the code compile cleanly with zero static analysis warnings?
2. Are all imports necessary and properly ordered?
3. Are all native resources, isolates, or streams safely closed in `finally` blocks?
4. Are all methods fully implemented without any placeholder shortcuts?
