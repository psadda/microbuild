require "test_helper"
require "tmpdir"
require "fileutils"
require "stringio"

class BuilderTest < Minitest::Test
  # ---------------------------------------------------------------------------
  # #initialize / compiler detection
  # ---------------------------------------------------------------------------
  def test_initializes_when_compiler_present
    # The CI environment has clang or gcc installed.
    assert_instance_of Microbuild::Builder, Microbuild::Builder.new
  end

  def test_compiler_type_is_known
    builder = Microbuild::Builder.new
    assert_includes [:clang, :gcc, :msvc], builder.compiler.type
  end

  def test_compiler_is_compiler_info_struct
    builder = Microbuild::Builder.new
    assert_instance_of Microbuild::CompilerInfo, builder.compiler
  end

  def test_compiler_info_has_ar_field
    builder = Microbuild::Builder.new
    # ar is expected to be present on any standard CI system
    refute_nil builder.compiler.ar
  end

  def test_compiler_info_ranlib_is_string_or_nil
    builder = Microbuild::Builder.new
    assert(builder.compiler.ranlib.nil? || builder.compiler.ranlib.is_a?(String))
  end

  def test_raises_when_no_compiler_found
    # Use an anonymous subclass that reports every command as unavailable.
    klass = Class.new(Microbuild::Builder) do
      private

      def command_available?(_cmd)
        false
      end
    end
    assert_raises(Microbuild::CompilerNotFoundError) { klass.new }
  end

  # ---------------------------------------------------------------------------
  # log accumulation
  # ---------------------------------------------------------------------------
  def test_log_is_empty_before_any_command
    builder = Microbuild::Builder.new
    assert_empty builder.log
  end

  def test_log_accumulates_entries_after_compile
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      builder.compile(src, obj)
      assert_equal 1, builder.log.size
      entry = builder.log.first
      assert entry.key?(:command), "log entry should have :command"
      assert entry.key?(:stdout),  "log entry should have :stdout"
      assert entry.key?(:stderr),  "log entry should have :stderr"
    end
  end

  def test_log_grows_with_each_invocation
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "main.c")
      obj = File.join(dir, "main.o")
      exe = File.join(dir, "main")
      File.write(src, "int main(void) { return 0; }\n")

      builder.compile(src, obj)
      builder.link_executable([obj], exe)
      assert_equal 2, builder.log.size
    end
  end

  # ---------------------------------------------------------------------------
  # stdout_sink / stderr_sink
  # ---------------------------------------------------------------------------
  def test_stdout_sink_receives_write_calls
    sink = StringIO.new
    builder = Microbuild::Builder.new(stdout_sink: sink)
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      builder.compile(src, obj)
      assert_kind_of String, sink.string
    end
  end

  def test_stderr_sink_receives_error_output
    sink = StringIO.new
    builder = Microbuild::Builder.new(stderr_sink: sink)
    Dir.mktmpdir do |dir|
      src = File.join(dir, "broken.c")
      obj = File.join(dir, "broken.o")
      File.write(src, "this is not valid C code {\n")

      builder.compile(src, obj)
      refute_empty sink.string, "stderr sink should have received error output"
    end
  end

  def test_same_object_can_be_used_for_both_sinks
    sink = StringIO.new
    builder = Microbuild::Builder.new(stdout_sink: sink, stderr_sink: sink)
    assert_instance_of Microbuild::Builder, builder
  end

  def test_no_sinks_does_not_raise
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      assert builder.compile(src, obj), "expected compile to succeed"
    end
  end

  # ---------------------------------------------------------------------------
  # #compile
  # ---------------------------------------------------------------------------
  def test_compile_c_source_returns_true_and_creates_object_file
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      result = builder.compile(src, obj, flags: [], include_paths: [], definitions: [])
      assert result, "expected compile to return true"
      assert File.exist?(obj), "expected object file to be created"
    end
  end

  def test_compile_cxx_source_returns_true_and_creates_object_file
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.cpp")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main() { return 0; }\n")

      result = builder.compile(src, obj, flags: [], include_paths: [], definitions: [])
      assert result, "expected compile to return true"
      assert File.exist?(obj), "expected object file to be created"
    end
  end

  def test_compile_with_include_paths_and_definitions
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      inc_dir = File.join(dir, "include")
      FileUtils.mkdir_p(inc_dir)
      File.write(File.join(inc_dir, "config.h"), "#define ANSWER 42\n")

      src = File.join(dir, "main.c")
      obj = File.join(dir, "main.o")
      File.write(src, "#include <config.h>\nint main(void) { return ANSWER - ANSWER; }\n")

      result = builder.compile(
        src, obj,
        flags: [],
        include_paths: [inc_dir],
        definitions: ["UNUSED=1"]
      )
      assert result, "expected compile to return true"
      assert File.exist?(obj), "expected object file to be created"
    end
  end

  def test_compile_broken_source_returns_false
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "broken.c")
      obj = File.join(dir, "broken.o")
      File.write(src, "this is not valid C code {\n")

      result = builder.compile(src, obj, flags: [], include_paths: [], definitions: [])
      refute result, "expected compile to return false for invalid source"
    end
  end

  # ---------------------------------------------------------------------------
  # #link_executable
  # ---------------------------------------------------------------------------
  def test_link_executable_creates_executable
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "main.c")
      obj = File.join(dir, "main.o")
      exe = File.join(dir, "main")
      File.write(src, "int main(void) { return 0; }\n")

      builder.compile(src, obj)
      result = builder.link_executable([obj], exe)
      assert result, "expected link_executable to return true"
      assert File.exist?(exe), "expected executable to be created"
    end
  end

  def test_link_executable_missing_object_returns_false
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      result = builder.link_executable([File.join(dir, "nonexistent.o")], File.join(dir, "out"))
      refute result, "expected link_executable to return false for missing object file"
    end
  end

  # ---------------------------------------------------------------------------
  # #link_static
  # ---------------------------------------------------------------------------
  def test_link_static_creates_archive
    builder = Microbuild::Builder.new
    skip("ar not available") unless builder.compiler.ar

    Dir.mktmpdir do |dir|
      src = File.join(dir, "util.c")
      obj = File.join(dir, "util.o")
      lib = File.join(dir, "libutil.a")
      File.write(src, "int add(int a, int b) { return a + b; }\n")

      builder.compile(src, obj)
      result = builder.link_static([obj], lib)
      assert result, "expected link_static to return true"
      assert File.exist?(lib), "expected static library to be created"
    end
  end

  def test_link_static_returns_false_when_ar_unavailable
    # Subclass whose compiler reports no archiver available.
    klass = Class.new(Microbuild::Builder) do
      private

      def detect_compiler!
        Microbuild::CompilerInfo.new(:gcc, "gcc", "g++", "g++", nil, nil)
      end
    end
    builder = klass.new
    refute builder.link_static([], "/tmp/fake.a"), "expected false when ar is unavailable"
  end

  # ---------------------------------------------------------------------------
  # #link_shared
  # ---------------------------------------------------------------------------
  def test_link_shared_creates_shared_library
    builder = Microbuild::Builder.new
    skip("MSVC shared linking not tested here") if builder.compiler.type == :msvc

    Dir.mktmpdir do |dir|
      src = File.join(dir, "util.c")
      obj = File.join(dir, "util.o")
      lib = File.join(dir, "libutil.so")
      File.write(src, "int add(int a, int b) { return a + b; }\n")

      builder.compile(src, obj, flags: ["-fPIC"])
      result = builder.link_shared([obj], lib)
      assert result, "expected link_shared to return true"
      assert File.exist?(lib), "expected shared library to be created"
    end
  end

  # ---------------------------------------------------------------------------
  # incremental build: up-to-date skipping and force: override
  # ---------------------------------------------------------------------------
  def test_compile_skips_when_output_is_up_to_date
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      builder.compile(src, obj)
      assert_equal 1, builder.log.size

      # Make src appear older than obj so the output is considered up-to-date.
      past = File.mtime(obj) - 1
      File.utime(past, past, src)

      result = builder.compile(src, obj)
      assert result, "expected skipped compile to return true"
      assert_equal 1, builder.log.size, "log should not grow when step is skipped"
    end
  end

  def test_compile_force_overrides_up_to_date
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      builder.compile(src, obj)

      past = File.mtime(obj) - 1
      File.utime(past, past, src)

      result = builder.compile(src, obj, force: true)
      assert result, "expected forced compile to return true"
      assert_equal 2, builder.log.size, "log should grow when force: true"
    end
  end

  def test_link_executable_skips_when_output_is_up_to_date
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "main.c")
      obj = File.join(dir, "main.o")
      exe = File.join(dir, "main")
      File.write(src, "int main(void) { return 0; }\n")

      builder.compile(src, obj)
      builder.link_executable([obj], exe)
      assert_equal 2, builder.log.size

      # Make obj appear older than exe.
      past = File.mtime(exe) - 1
      File.utime(past, past, obj)

      result = builder.link_executable([obj], exe)
      assert result, "expected skipped link_executable to return true"
      assert_equal 2, builder.log.size, "log should not grow when step is skipped"
    end
  end

  def test_link_executable_force_overrides_up_to_date
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "main.c")
      obj = File.join(dir, "main.o")
      exe = File.join(dir, "main")
      File.write(src, "int main(void) { return 0; }\n")

      builder.compile(src, obj)
      builder.link_executable([obj], exe)

      past = File.mtime(exe) - 1
      File.utime(past, past, obj)

      result = builder.link_executable([obj], exe, force: true)
      assert result, "expected forced link_executable to return true"
      assert_equal 3, builder.log.size, "log should grow when force: true"
    end
  end

  def test_link_static_skips_when_output_is_up_to_date
    builder = Microbuild::Builder.new
    skip("ar not available") unless builder.compiler.ar

    Dir.mktmpdir do |dir|
      src = File.join(dir, "util.c")
      obj = File.join(dir, "util.o")
      lib = File.join(dir, "libutil.a")
      File.write(src, "int add(int a, int b) { return a + b; }\n")

      builder.compile(src, obj)
      builder.link_static([obj], lib)
      log_size = builder.log.size

      past = File.mtime(lib) - 1
      File.utime(past, past, obj)

      result = builder.link_static([obj], lib)
      assert result, "expected skipped link_static to return true"
      assert_equal log_size, builder.log.size, "log should not grow when step is skipped"
    end
  end

  def test_link_shared_skips_when_output_is_up_to_date
    builder = Microbuild::Builder.new
    skip("MSVC shared linking not tested here") if builder.compiler.type == :msvc

    Dir.mktmpdir do |dir|
      src = File.join(dir, "util.c")
      obj = File.join(dir, "util.o")
      lib = File.join(dir, "libutil.so")
      File.write(src, "int add(int a, int b) { return a + b; }\n")

      builder.compile(src, obj, flags: ["-fPIC"])
      builder.link_shared([obj], lib)
      log_size = builder.log.size

      past = File.mtime(lib) - 1
      File.utime(past, past, obj)

      result = builder.link_shared([obj], lib)
      assert result, "expected skipped link_shared to return true"
      assert_equal log_size, builder.log.size, "log should not grow when step is skipped"
    end
  end
end
