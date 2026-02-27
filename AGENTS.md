# AGENTS.md

## Testing Guidelines: Reducing Reliance on Stubs and Mocks

### Core Principles

1. **Test postconditions, not implementation details.** Assert on observable state
   after a method runs — return values, instance variables, side effects like `ENV`
   changes — rather than verifying how many times an internal method was called or
   what arguments it received. Call-count assertions test the mock, not the code.

2. **Extract pure logic into separately testable methods.** When a method mixes
   subprocess execution with data processing, split it in two: a thin wrapper that
   runs the subprocess, and a pure method that processes the output. The pure method
   can be tested directly with crafted inputs, eliminating the need to mock the
   subprocess layer entirely.

   ```ruby
   # Before — must mock Open3 to test ENV parsing
   def run_vcvarsall(vcvarsall)
     stdout, _, status = Open3.capture3(…)
     return unless status.success?
     stdout.each_line { |l| … ENV[k] = v }
   end

   # After — load_vcvarsall is testable without any mocks
   def run_vcvarsall(vcvarsall)
     stdout, _, status = Open3.capture3(…)
     return unless status.success?
     load_vcvarsall(stdout)
   end

   def load_vcvarsall(output)
     output.each_line { |l| … ENV[k] = v }
   end
   ```

3. **Mock at the subprocess boundary, not at library APIs.** Instead of stubbing
   `Open3.capture3` or `File.exist?`, define thin wrapper methods that encapsulate
   each subprocess call (e.g. `run_vswhere`, `run_vcvarsall`). Override only those
   wrappers in test subclasses. This keeps tests resilient to changes in how
   subprocess calls are structured internally.

4. **Use the real file system instead of stubbing `File`.** Create temporary
   directories with `Dir.mktmpdir` and populate them with the files your code
   expects. This verifies actual path-derivation logic and avoids false confidence
   from stubs that might not match real behaviour.

5. **Avoid `allocate` for test instances.** Needing a partially-initialised object
   is a sign that the method under test should be extracted, or that the test should
   construct a proper instance with controlled constructor behaviour (e.g. via a
   subclass that overrides only the subprocess-calling methods).

6. **Keep the mock surface minimal.** A test subclass should override only the
   methods that would trigger real subprocess calls. All orchestration and logic
   methods should run their real implementations so that bugs in those paths are
   caught.

### Anti-patterns

| Anti-pattern | Why it's harmful |
|---|---|
| Asserting call counts or argument lists of internal methods | Tests the mock, not the code; breaks when internals are refactored |
| Stubbing `Open3`, `File`, `IO`, or other stdlib classes | Brittle; silently masks real behaviour changes |
| Using `.allocate` to skip constructors | Creates objects in invalid states; hides constructor bugs |
| Overriding more methods than necessary in test subclasses | Masks bugs in the un-tested real implementations |

### Practical Checklist

- [ ] Does each assertion check an **observable postcondition** (return value,
      attribute, side effect)?
- [ ] Are subprocess calls wrapped in **thin, overrideable methods**?
- [ ] Is pure logic **extracted** so it can be tested with direct input?
- [ ] Are file-system interactions tested against a **real `tmpdir`**?
- [ ] Is the test subclass overriding **only subprocess wrappers**, nothing else?
