# Contract: Rake Task

The primary user-facing trigger (FR-002). Registered with the host application
by the gem's railtie — no `require`/`load` line is needed in the host `Rakefile`.

## Task

```text
rake openapi:generate
```

## Behavior

1. Loads the host Rails environment (depends on the `:environment` task).
2. Builds a `Configuration` from `RailsOpenapiGenerator.configuration` (whatever
   the host set via `RailsOpenapiGenerator.configure`).
3. Calls `RailsOpenapiGenerator::Generator#generate`.
4. Prints the `GenerationReport` summary to stdout: processed count, skipped
   routes with reasons, and warnings (FR-014).

The task contains no generation logic — it only wires environment → Generator →
report output (Constitution IV).

## Options

Overrides are passed as environment variables so the task stays argument-free:

| Variable | Effect |
|----------|--------|
| `OUTPUT` | Overrides `configuration.output_path` for this run. |
| `FORMAT` | Overrides `configuration.format` (`json` / `yaml`). |

```text
rake openapi:generate OUTPUT=tmp/openapi.yaml FORMAT=yaml
```

## Exit status

| Situation | Exit code |
|-----------|-----------|
| Document generated (including with warnings) | 0 |
| `ConfigurationError` (bad config / unwritable output) | non-zero |

## Parity

The task MUST produce a document identical to the CLI and the library API for
the same `Configuration` (Constitution IV).
