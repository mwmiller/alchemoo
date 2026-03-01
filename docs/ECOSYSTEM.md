# MOO Ecosystem Guide

This guide provides a comprehensive overview of the MOO ecosystem, based on resources from [lisdude.com/moo](https://lisdude.com/moo/). It serves as a reference for Alchemoo development, testing, and roadmap planning.

## 1. MOO Server Cores (Engines)

These are the server implementations. Alchemoo aims to be a modern, BEAM-based alternative to these.

### 1.1. Reference Servers
*   **LambdaMOO (1.8.1):** The "Gold Standard". Any modern MOO must maintain high compatibility with 1.8.1.
*   **ToastStunt:** The current state-of-the-art C-based fork. Supports 64-bit integers, SQLite, PCRE, and Argon2id.
*   **Stunt:** Introduced multiple inheritance and Ordered Maps (Dictionaries).

### 1.2. Modern Reimplementations
*   **EtaMOO (Haskell):** A multi-threaded Haskell implementation.
*   **moor (Rust):** A systems-level reimplementation written in Rust. [Source Code](https://codeberg.org/timbran/moor). Focuses on memory safety, high performance, and modern language extensions.

## 2. Modern Learnings & Architectural Patterns

Modern implementations like **moor** and **ToastStunt** provide several key areas of learning for Alchemoo:

### 2.1. Concurrency Models
Traditional MOO is single-threaded. Modern servers take different approaches:
*   **Optimistic Concurrency (MVCC):** moor uses a Multi-Version Concurrency Control model. Tasks run in parallel and are committed only if no conflicts occur.
*   **BEAM Actor Model:** Alchemoo's current approach using lightweight processes per task provides isolation, but database-level transactions (perhaps inspired by MVCC) could further improve consistency.

### 2.2. Language Extensions
Modern cores expect more than just the basic MOO types:
*   **Maps/Dictionaries:** Associative arrays are standard in modern MOO (Stunt/moor).
*   **Anonymous Objects (Waifs):** Light-weight, garbage-collected objects that don't live in the permanent object tree.
*   **Lambdas & Closures:** moor adds first-class anonymous functions to the MOO language.

### 2.3. Developer Experience (DX)
*   **IDE Integration:** moor includes a built-in web frontend providing an IDE-like experience for in-world programming via REST and WebSockets.
*   **64-bit & Unicode:** Ensuring 64-bit integer support and native UTF-8 handling (already a priority for Alchemoo).

## 3. MOO Core Databases (Starting Points)

These are the `.db` files that provide the initial world state. They are essential for testing Alchemoo's parser and interpreter.

### 2.1. Minimal Cores (Priority for TDD)
*   **Ultraminimal.db:** Only `#0` (System Object). Ideal for testing basic boot-up.
*   **Minimalest.db:** `#0` and `#1` (Wizard).
*   **Minimal.db:** 3-4 objects. Standard baseline for new server implementations.

### 2.2. Standard Cores (Compatibility Targets)
*   **LambdaCore (2004/2018):** The base for almost every MOO in existence. Successfully loading this is a major milestone.
*   **JHCore:** Feature-rich core with better pronoun substitution and building systems. Successfully loading this tests advanced verb usage.

### 2.3. Feature-Rich Cores
*   **ToastCore:** Utilizes ToastStunt features (waifs, anon objects).
*   **OmegaCore:** Optimized for the Stunt server.

## 3. Key Roadmap Features (Inspired by Ecosystem)

Based on modern forks, Alchemoo should consider implementing:

*   **Datatypes:** Ordered Maps (Dictionaries) from Stunt, 64-bit Integers.
*   **Security:** Argon2id hashing for passwords (standard in ToastStunt).
*   **Regex:** PCRE support (Alchemoo currently uses Elixir's Regex, which is PCRE-compatible).
*   **Protocols:** MCP (MUD Client Protocol) version 2.1 is critical for modern clients.

## 4. Documentation Resources

*   **ToastStunt Programmer's Manual:** The most up-to-date manual for modern MOO programming.
*   **LambdaMOO Programmer's Manual:** The definitive reference for core language semantics.
*   **MCP 2.1 Specification:** Essential for implementing out-of-band communication.

## 5. Development Strategy for Alchemoo

### 5.1. Testing Tier List
1.  **Tier 1 (Core):** `Minimal.db`. Ensure every verb executes correctly.
2.  **Tier 2 (Compatibility):** `LambdaCore`. Handle large object counts and property inheritance.
3.  **Tier 3 (Advanced):** `JHCore`. Verify complex building and pronoun logic.
4.  **Tier 4 (Modern):** `ToastCore`. Implement modern extensions like waifs.

### 5.2. Benchmarking
Use `EtaMOO` and `ToastStunt` as performance baselines for task execution and database lookups.

---
*Updated for Alchemoo Project - March 1, 2026*
