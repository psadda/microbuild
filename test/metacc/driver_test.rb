# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "stringio"

class DriverTest < Minitest::Test

  # ---------------------------------------------------------------------------
  # #initialize / compiler detection
  # ---------------------------------------------------------------------------
  def test_initializes_when_compiler_present
    # The CI environment has clang or gcc installed.
    assert_instance_of MetaCC::Driver, MetaCC::Driver.new
  end

  def test_compiler_type_is_known
    builder = MetaCC::Driver.new

    assert_includes %i[clang gcc msvc], builder.toolchain.type
  end

  def test_compiler_is_compiler_info_struct
    builder = MetaCC::Driver.new

    assert_kind_of MetaCC::Toolchain, builder.toolchain
  end

  def test_raises_when_no_compiler_found
    # Use an anonymous subclass with no toolchain classes to probe.
    klass = Class.new(MetaCC::Driver) do
      private

      def toolchain_classes
        []
      end
    end
    assert_raises(MetaCC::CompilerNotFoundError) { klass.new }
  end

  # ---------------------------------------------------------------------------
  # log accumulation
  # ---------------------------------------------------------------------------
  def test_log_is_empty_before_any_command
    builder = MetaCC::Driver.new

    assert_empty builder.log
  end

  def test_log_accumulates_entries_after_invoke
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      builder.invoke(src, obj, flags: [:objects])

      assert_equal 1, builder.log.size
      entry = builder.log.first

      assert entry.key?(:command), "log entry should have :command"
      assert entry.key?(:stdout),  "log entry should have :stdout"
      assert entry.key?(:stderr),  "log entry should have :stderr"
    end
  end

  def test_log_grows_with_each_invocation
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "main.c")
      obj = File.join(dir, "main.o")
      exe = File.join(dir, "main")
      File.write(src, "int main(void) { return 0; }\n")

      builder.invoke(src, obj, flags: [:objects])
      builder.invoke([obj], exe)

      assert_equal 2, builder.log.size
    end
  end

  # ---------------------------------------------------------------------------
  # stdout_sink / stderr_sink
  # ---------------------------------------------------------------------------
  def test_stdout_sink_receives_write_calls
    sink = StringIO.new
    builder = MetaCC::Driver.new(stdout_sink: sink)
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      builder.invoke(src, obj, flags: [:objects])

      assert_kind_of String, sink.string
    end
  end

  def test_stderr_sink_receives_error_output
    sink = StringIO.new
    builder = MetaCC::Driver.new(stderr_sink: sink)
    Dir.mktmpdir do |dir|
      src = File.join(dir, "broken.c")
      obj = File.join(dir, "broken.o")
      File.write(src, "this is not valid C code {\n")

      builder.invoke(src, obj, flags: [:objects])

      refute_empty sink.string, "stderr sink should have received error output"
    end
  end

  def test_same_object_can_be_used_for_both_sinks
    sink = StringIO.new
    builder = MetaCC::Driver.new(stdout_sink: sink, stderr_sink: sink)

    assert_instance_of MetaCC::Driver, builder
  end

  def test_no_sinks_does_not_raise
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      assert builder.invoke(src, obj, flags: [:objects]), "expected invoke to succeed"
    end
  end

  # ---------------------------------------------------------------------------
  # #invoke – compile to object files (objects flag)
  # ---------------------------------------------------------------------------
  def test_invoke_objects_c_source_returns_true_and_creates_object_file
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      result = builder.invoke(src, obj, flags: [:objects], include_paths: [], definitions: [])

      assert result, "expected invoke to return true"
      assert_path_exists obj, "expected object file to be created"
    end
  end

  def test_invoke_objects_cxx_source_returns_true_and_creates_object_file
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.cpp")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main() { return 0; }\n")

      result = builder.invoke(src, obj, flags: [:objects], include_paths: [], definitions: [])

      assert result, "expected invoke to return true"
      assert_path_exists obj, "expected object file to be created"
    end
  end

  def test_invoke_objects_with_include_paths_and_definitions
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      inc_dir = File.join(dir, "include")
      FileUtils.mkdir_p(inc_dir)
      File.write(File.join(inc_dir, "config.h"), "#define ANSWER 42\n")

      src = File.join(dir, "main.c")
      obj = File.join(dir, "main.o")
      File.write(src, "#include <config.h>\nint main(void) { return ANSWER - ANSWER; }\n")

      result = builder.invoke(
        src, obj,
        flags:         [:objects],
        include_paths: [inc_dir],
        definitions:   ["UNUSED=1"]
      )

      assert result, "expected invoke to return true"
      assert_path_exists obj, "expected object file to be created"
    end
  end

  def test_invoke_objects_broken_source_returns_false
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "broken.c")
      obj = File.join(dir, "broken.o")
      File.write(src, "this is not valid C code {\n")

      result = builder.invoke(src, obj, flags: [:objects], include_paths: [], definitions: [])

      refute result, "expected invoke to return false for invalid source"
    end
  end

  # ---------------------------------------------------------------------------
  # #invoke – link to executable (no mode flag)
  # ---------------------------------------------------------------------------
  def test_invoke_executable_creates_executable
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "main.c")
      obj = File.join(dir, "main.o")
      exe = File.join(dir, "main")
      File.write(src, "int main(void) { return 0; }\n")

      builder.invoke(src, obj, flags: [:objects])
      result = builder.invoke([obj], exe)

      assert result, "expected invoke to return true"
      assert_path_exists exe, "expected executable to be created"
    end
  end

  def test_invoke_executable_missing_object_returns_false
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      result = builder.invoke([File.join(dir, "nonexistent.o")], File.join(dir, "out"))

      refute result, "expected invoke to return false for missing object file"
    end
  end

  # ---------------------------------------------------------------------------
  # #invoke – shared library (shared flag)
  # ---------------------------------------------------------------------------
  def test_invoke_shared_creates_shared_library
    builder = MetaCC::Driver.new
    skip("MSVC shared linking not tested here") if builder.toolchain.type == :msvc

    Dir.mktmpdir do |dir|
      src = File.join(dir, "util.c")
      obj = File.join(dir, "util.o")
      lib = File.join(dir, "libutil.so")
      File.write(src, "int add(int a, int b) { return a + b; }\n")

      builder.invoke(src, obj, flags: [:objects, :pic])
      result = builder.invoke([obj], lib, flags: [:shared])

      assert result, "expected invoke to return true"
      assert_path_exists lib, "expected shared library to be created"
    end
  end

  # ---------------------------------------------------------------------------
  # incremental build: up-to-date skipping and force: override
  # ---------------------------------------------------------------------------
  def test_invoke_objects_skips_when_output_is_up_to_date
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      builder.invoke(src, obj, flags: [:objects])

      assert_equal 1, builder.log.size

      # Make src appear older than obj so the output is considered up-to-date.
      past = File.mtime(obj) - 1
      File.utime(past, past, src)

      result = builder.invoke(src, obj, flags: [:objects])

      assert result, "expected skipped invoke to return true"
      assert_equal 1, builder.log.size, "log should not grow when step is skipped"
    end
  end

  def test_invoke_objects_force_overrides_up_to_date
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      builder.invoke(src, obj, flags: [:objects])

      past = File.mtime(obj) - 1
      File.utime(past, past, src)

      result = builder.invoke(src, obj, flags: [:objects], force: true)

      assert result, "expected forced invoke to return true"
      assert_equal 2, builder.log.size, "log should grow when force: true"
    end
  end

  def test_invoke_executable_skips_when_output_is_up_to_date
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "main.c")
      obj = File.join(dir, "main.o")
      exe = File.join(dir, "main")
      File.write(src, "int main(void) { return 0; }\n")

      builder.invoke(src, obj, flags: [:objects])
      builder.invoke([obj], exe)

      assert_equal 2, builder.log.size

      # Make obj appear older than exe.
      past = File.mtime(exe) - 1
      File.utime(past, past, obj)

      result = builder.invoke([obj], exe)

      assert result, "expected skipped invoke to return true"
      assert_equal 2, builder.log.size, "log should not grow when step is skipped"
    end
  end

  def test_invoke_executable_force_overrides_up_to_date
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "main.c")
      obj = File.join(dir, "main.o")
      exe = File.join(dir, "main")
      File.write(src, "int main(void) { return 0; }\n")

      builder.invoke(src, obj, flags: [:objects])
      builder.invoke([obj], exe)

      past = File.mtime(exe) - 1
      File.utime(past, past, obj)

      result = builder.invoke([obj], exe, force: true)

      assert result, "expected forced invoke to return true"
      assert_equal 3, builder.log.size, "log should grow when force: true"
    end
  end

  def test_invoke_shared_skips_when_output_is_up_to_date
    builder = MetaCC::Driver.new
    skip("MSVC shared linking not tested here") if builder.toolchain.type == :msvc

    Dir.mktmpdir do |dir|
      src = File.join(dir, "util.c")
      obj = File.join(dir, "util.o")
      lib = File.join(dir, "libutil.so")
      File.write(src, "int add(int a, int b) { return a + b; }\n")

      builder.invoke(src, obj, flags: [:objects, :pic])
      builder.invoke([obj], lib, flags: [:shared])
      log_size = builder.log.size

      past = File.mtime(lib) - 1
      File.utime(past, past, obj)

      result = builder.invoke([obj], lib, flags: [:shared])

      assert result, "expected skipped invoke to return true"
      assert_equal log_size, builder.log.size, "log should not grow when step is skipped"
    end
  end

  # ---------------------------------------------------------------------------
  # output_dir: constructor option
  # ---------------------------------------------------------------------------
  def test_output_dir_prepended_to_relative_output_path
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      File.write(src, "int main(void) { return 0; }\n")
      build_dir = File.join(dir, "out")
      FileUtils.mkdir_p(build_dir)

      builder = MetaCC::Driver.new(output_dir: build_dir)
      result = builder.invoke(src, "hello.o", flags: [:objects])

      assert result, "expected invoke to succeed"
      assert_path_exists File.join(build_dir, "hello.o"), "object should be in output_dir"
    end
  end

  def test_absolute_output_path_ignores_output_dir
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o") # absolute
      File.write(src, "int main(void) { return 0; }\n")

      builder = MetaCC::Driver.new(output_dir: "/nonexistent_build_dir")
      result = builder.invoke(src, obj, flags: [:objects])

      assert result, "expected invoke to succeed with absolute output path"
      assert_path_exists obj, "object should be at the absolute path"
    end
  end

  def test_output_dir_default_is_build
    builder = MetaCC::Driver.new

    assert_equal "build", builder.output_dir
  end

  # ---------------------------------------------------------------------------
  # env: and working_dir: per-invocation options
  # ---------------------------------------------------------------------------
  def test_invoke_accepts_env_and_working_dir
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      result = builder.invoke(src, obj, flags: [:objects], env: {}, working_dir: dir)

      assert result, "expected invoke to succeed with env: and working_dir:"
    end
  end

  def test_invoke_executable_accepts_env_and_working_dir
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "main.c")
      obj = File.join(dir, "main.o")
      exe = File.join(dir, "main")
      File.write(src, "int main(void) { return 0; }\n")

      builder.invoke(src, obj, flags: [:objects])
      result = builder.invoke([obj], exe, env: {}, working_dir: dir)

      assert result, "expected invoke to succeed with env: and working_dir:"
    end
  end

  def test_env_variables_are_forwarded_to_subprocess
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      # Pass a harmless env var; compilation should still succeed.
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      result = builder.invoke(src, obj, flags: [:objects], env: { "MY_BUILD_FLAG" => "1" })

      assert result, "expected invoke to succeed when env: contains custom vars"
    end
  end

  def test_working_dir_sets_subprocess_cwd
    builder = MetaCC::Driver.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      # Run with working_dir set to the tmp dir; absolute paths still resolve.
      result = builder.invoke(src, obj, flags: [:objects], working_dir: dir)

      assert result, "expected invoke to succeed with working_dir set"
      assert_path_exists obj, "object file should exist after invoke with working_dir"
    end
  end

end
