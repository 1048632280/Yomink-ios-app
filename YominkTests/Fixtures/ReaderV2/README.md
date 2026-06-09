# ReaderV2 Fixtures

Phase 0 uses these fixed TXT fixtures for manual import and smoke testing:

- `short-story.txt`: short chapter and small-page sanity checks.
- `normal-long.txt`: ordinary multi-chapter reading checks.
- `large-30mb.generated.txt`: generated stress fixture, intentionally ignored by git.

Generate the 30MB fixture from this directory on a machine with Swift:

```sh
swift generate_large_fixture.swift
```

The generated file is deterministic and exactly 30 MiB. Keep it out of git.
