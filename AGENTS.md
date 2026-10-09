# Project Instructions

This is a personal diary and task management application built with Flutter.

## Project goals

The application targets Android and Windows.

The current version is local-first and uses SQLite.
Cloud synchronization may be added later, but it is not part of v0.1.

Read `docs/PRODUCT.md` when product behavior or scope is relevant.
Read `docs/ARCHITECTURE.md` when changing project structure or data flow.
Read `docs/DECISIONS.md` before making an architectural decision that may conflict with an existing one.

## Development rules

- Do not add features outside the requested scope.
- Prefer simple solutions over unnecessary abstractions.
- Do not introduce a new framework, package, or architectural pattern without explaining why it is needed.
- Preserve existing behavior unless the task explicitly asks to change it.
- Keep Android and Windows compatibility in mind.
- Run relevant formatting, static analysis, and tests after implementation.
- Fix failures caused by the requested change before considering the task complete.

## Working style

For architectural or product decisions:
- analyze the problem first;
- explain important tradeoffs;
- do not silently make major decisions.

For ordinary implementation tasks:
- inspect the relevant code;
- implement the requested scope;
- verify the result;
- summarize what changed and how to test it.

When the request is ambiguous in a way that materially affects product behavior, ask before choosing.
Do not ask about minor implementation details that can be safely inferred.

## Learning goal

The project owner is learning how a complete application works.

After implementing a meaningful feature, explain:
- which files were changed;
- the responsibility of those files;
- the data flow of the feature;
- how the implementation can be manually verified.