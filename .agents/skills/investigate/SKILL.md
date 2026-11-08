---
name: investigate
description: Systematic root-cause debugging and forensic analysis for Dart and Flutter applications.
---

# Systematic Investigation & Root-Cause Debugging

## Core Principle
**Never patch symptoms. Always locate and prove the root cause before writing fix code.** Speculative fixes introduce regressions, bloat architectures, and obscure the underlying defect.

---

## The 4-Phase Investigation Workflow

### Phase 1: Problem Isolation & Deterministic Reproduction
1. **Capture the Failure State:**
   - Record exact error messages, stack traces, and relevant platform/device logs (`adb logcat`, Flutter runtime crash dumps).
   - Identify whether the defect occurs in the UI isolate, background Dart isolate, platform channel, or native FFI layer.
2. **Minimal Reproduction:**
   - Isolate the minimal sequence of events, user interactions, or data inputs required to trigger the failure.
   - If feasible, reproduce with a targeted unit test (`dart test`) or widget test (`flutter test`).

### Phase 2: Execution Path & State Tracing
1. **Trace Data & Message Flow:**
   - Map data transitions across isolate boundaries (`SendPort` / `ReceivePort`).
   - Audit stream pipelines for unhandled errors, paused streams, or dropped events.
   - Trace native FFI pointer lifecycles: check for premature deallocation, use-after-free, or alignment issues.
2. **Inspect Concurrency & State Mutations:**
   - Check for race conditions between asynchronous futures or concurrent isolate messages.
   - Verify immutable state transitions in state managers (Riverpod, Bloc, ChangeNotifier).

### Phase 3: Falsifiable Hypothesis Testing
1. **Formulate Hypotheses:**
   - Propose 2-3 specific, testable explanations for why the failure occurred.
2. **Gather Concrete Evidence:**
   - Add diagnostic assertions or targeted logging to confirm or eliminate each hypothesis.
   - Inspect memory consumption, pointer addresses, or message queues.
   - Never apply speculative code modifications during this phase.

### Phase 4: Remediation & Regression Verification
1. **Address the Root Mechanism:**
   - Implement the minimal, robust change that rectifies the confirmed defect.
2. **Verify Against Regressions:**
   - Re-run the reproduction test to ensure the failure no longer occurs.
   - Run the broader test suite and static analysis (`dart analyze`) to confirm zero secondary fallout.
   - Document the root cause, mechanism of failure, and resolution rationale.
