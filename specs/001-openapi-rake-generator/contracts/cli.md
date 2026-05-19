# Contract: CLI Executable

Shipped to satisfy Constitution IV (Dual Interface Parity). The CLI is a thin
wrapper: it parses arguments, boots the host Rails environment, then calls the
same `RailsOpenapiGenerator::Generator#generate` the rake task uses. It contains
no generation logic of its own.

## Invocation

```text
rails-openapi-generator [options]
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--rails-root PATH` | Directory of the host Rails app to boot. | current directory |
| `--output PATH` | Output document path. | `Configuration#output_path` |
| `--format FORMAT` | `json` or `yaml`. | inferred from output path |
| `--help` | Print usage and exit 0. | — |
| `--version` | Print gem version and exit 0. | — |

## Text protocol (Constitution IV)

- Generated document is written to the `--output` file.
- The `GenerationReport` summary (processed / skipped / warnings) is written to
  **stdout**.
- Diagnostics and error messages are written to **stderr**.
- Exit code is `0` on a completed run (warnings allowed), non-zero on failure.

## Behavior

1. Resolve `--rails-root`; if `config/environment.rb` is absent, write an error
   to stderr and exit non-zero.
2. `require` the host app's `config/environment.rb`.
3. Build a `Configuration`, applying `--output` / `--format` overrides.
4. Call `Generator#generate`; print the report to stdout.

## Exit status

| Situation | Exit code |
|-----------|-----------|
| Document generated (including with warnings) | 0 |
| Rails root invalid / environment fails to load | non-zero |
| `ConfigurationError` | non-zero |

## Parity

For the same effective `Configuration`, the CLI MUST produce a document
identical to the rake task and the library API (Constitution IV).
