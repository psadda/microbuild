require "test_helper"
require "tmpdir"
require "fileutils"

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

  def test_raises_when_no_compiler_found
    # Use an anonymous subclass that reports every compiler as unavailable.
    klass = Class.new(Microbuild::Builder) do
      private

      def compiler_available?(_cmd)
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
      builder.link([obj], exe)
      assert_equal 2, builder.log.size
    end
  end

  # ---------------------------------------------------------------------------
  # log_sink
  # ---------------------------------------------------------------------------
  def test_log_sink_is_called_for_each_command
    received = []
    sink = ->(entry) { received << entry }
    builder = Microbuild::Builder.new(log_sink: sink)
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      builder.compile(src, obj)
      assert_equal 1, received.size
      assert received.first.key?(:stdout)
    end
  end

  def test_no_log_sink_does_not_raise
    builder = Microbuild::Builder.new(log_sink: nil)
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
  # #link
  # ---------------------------------------------------------------------------
  def test_link_valid_objects_returns_true_and_creates_executable
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      src = File.join(dir, "main.c")
      obj = File.join(dir, "main.o")
      exe = File.join(dir, "main")
      File.write(src, "int main(void) { return 0; }\n")

      builder.compile(src, obj, flags: [], include_paths: [], definitions: [])
      result = builder.link([obj], exe)
      assert result, "expected link to return true"
      assert File.exist?(exe), "expected executable to be created"
    end
  end

  def test_link_missing_object_file_returns_false
    builder = Microbuild::Builder.new
    Dir.mktmpdir do |dir|
      exe = File.join(dir, "output")
      result = builder.link([File.join(dir, "nonexistent.o")], exe)
      refute result, "expected link to return false for missing object file"
    end
  end
end
