# Copilot Instructions

## Project Overview

`metacc` is a small C/C++ compiler driver written in Ruby. It wraps Clang, GCC,
MSVC, clang-cl, and TinyCC behind a uniform Ruby API (`MetaCC::Driver`) and a
command-line interface (`MetaCC::CLI`).  The gem is still at version 0.1.0 and is
the author's personal experiment in vibe-coding.

## Repository Layout

```
lib/
  metacc.rb              # Entry point; defines MetaCC::VERSION
  metacc/
    toolchain.rb         # Toolchain base class and all concrete subclasses
                         #   (GnuToolchain, ClangToolchain, MsvcToolchain,
                         #    ClangClToolchain, TinyccToolchain)
    driver.rb            # MetaCC::Driver – flag translation + invocation
    cli.rb               # MetaCC::CLI   – OptionParser-based CLI
test/
  test_helper.rb
  metacc/
    toolchain_test.rb
    driver_test.rb
    cli_test.rb
```

## Building & Testing

```bash
bundle install
bundle exec rake        # runs the full test suite (Minitest)
bundle exec rubocop     # lint with RuboCop (rubocop-minitest, rubocop-rake plugins)
```

## Code Style

- Ruby 3.2+; all files begin with `# frozen_string_literal: true`.
- Double-quoted strings throughout (`EnforcedStyle: double_quotes`).
- RuboCop config is in `.rubocop.yml`; run `bundle exec rubocop -a` for
  auto-correctable offenses.

## Testing Guidelines

Follow the principles in `AGENTS.md`:

1. **Assert postconditions**, not call counts or argument lists.
2. **Extract pure logic** into separately testable methods so subprocess calls
   don't need to be mocked.
3. **Wrap subprocess calls** in thin, overrideable methods; override only those
   in test subclasses.
4. **Use real temporary directories** (`Dir.mktmpdir`) instead of stubbing `File`.
5. **Don't use `.allocate`** to construct test instances.

Tests live in `test/metacc/` and follow the `*_test.rb` naming convention.
Run a single test file with:

```bash
bundle exec ruby -Ilib:test test/metacc/driver_test.rb
```

## Key Design Decisions

- `Driver#invoke` accepts an array of universal flag symbols (e.g. `:o2`,
  `:debug`, `:cxx17`) defined in `Driver::RECOGNIZED_FLAGS` and delegates
  translation to the active toolchain via `Toolchain#flags`.
- Per-toolchain native flags are passed through `xflags:` as a
  `Hash{Class => Array<String>}`.
- `MsvcToolchain` auto-discovers Visual Studio using `vswhere.exe` when
  `cl.exe` is not already on PATH, then runs `vcvarsall.bat` to populate `ENV`.
- `TinyccToolchain` is C-only; it reports `languages` as `[:c]`.
