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

## Feature development workflow

当任务涉及新增或明显修改用户功能、业务逻辑、数据流、
数据库结构或跨多个模块的行为时，
使用 `$guided-feature-development` skill。

在该 skill 要求确认方案时，不要在得到确认之前开始修改代码。

对于拼写、简单文案、微小样式调整等低风险修改，
不需要强制使用完整流程。

Skill file: [.agents/skills/guided-feature-development/SKILL.md](.agents/skills/guided-feature-development/SKILL.md)

## Local Windows test build

After a successful Windows build, copy dairy.exe, its runtime DLLs and the
complete data/ resource directory to F:\project\dairy (the owner's main
checkout, not a Codex worktree). Keep the local bundle ignored by Git and
close any running test application before refreshing it.
