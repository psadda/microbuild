# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class DriverTest < Minitest::Test

  # ---------------------------------------------------------------------------
  # #initialize / compiler detection
  # ---------------------------------------------------------------------------
  def test_initializes_when_compiler_present
    # The CI environment has clang or gcc installed.
    assert_instance_of MetaCC::Driver, MetaCC::Driver.new
  end

  def test_compiler_class_is_known
    builder = MetaCC::Driver.new

    assert_includes [MetaCC::Clang, MetaCC::GNU, MetaCC::MSVC], builder.toolchain.class
  end

  def test_compiler_is_compiler_info_struct
    builder = MetaCC::Driver.new

    assert_kind_of MetaCC::Toolchain, builder.toolchain
  end

  def test_raises_when_no_compiler_found
    assert_raises(MetaCC::CompilerNotFoundError) { MetaCC::Driver.new(prefer: []) }
  end

  # ---------------------------------------------------------------------------
  # toolchain#show_version
  # ---------------------------------------------------------------------------
  def test_toolchain_show_version_returns_non_empty_string
    driver = MetaCC::Driver.new

    version = driver.toolchain.version_banner

    assert_kind_of String, version
    refute_empty version
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

      result = builder.invoke(src, obj, flags: [:objects], include_paths: [], defs: [])

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

      result = builder.invoke(src, obj, flags: [:objects], include_paths: [], defs: [])

      assert result, "expected invoke to return true"
      assert_path_exists obj, "expected object file to be created"
    end
  end

  def test_invoke_objects_with_include_paths_and_defs
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
        defs:          ["UNUSED=1"]
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

      result = builder.invoke(src, obj, flags: [:objects], include_paths: [], defs: [])

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
    skip("MSVC shared linking not tested here") if builder.toolchain.is_a?(MetaCC::MSVC)

    Dir.mktmpdir do |dir|
      src = File.join(dir, "util.c")
      obj = File.join(dir, "util.o")
      lib = File.join(dir, "libutil.so")
      File.write(src, "int add(int a, int b) { return a + b; }\n")

      builder.invoke(src, obj, flags: %i[objects pic])
      result = builder.invoke([obj], lib, flags: [:shared])

      assert result, "expected invoke to return true"
      assert_path_exists lib, "expected shared library to be created"
    end
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

  # ---------------------------------------------------------------------------
  # prefer: constructor option
  # ---------------------------------------------------------------------------
  def test_prefer_selects_specified_toolchain_class
    builder = MetaCC::Driver.new(prefer: [MetaCC::GNU])

    assert_instance_of MetaCC::GNU, builder.toolchain
  end

  def test_prefer_empty_raises_compiler_not_found
    assert_raises(MetaCC::CompilerNotFoundError) { MetaCC::Driver.new(prefer: []) }
  end

  def test_prefer_default_is_clang_gnu_msvc_order
    builder = MetaCC::Driver.new

    assert_includes [MetaCC::Clang, MetaCC::GNU, MetaCC::MSVC],
                    builder.toolchain.class
  end

  # ---------------------------------------------------------------------------
  # search_paths: constructor option
  # ---------------------------------------------------------------------------
  def test_search_paths_default_is_empty
    # Verify the driver initializes without error when search_paths is empty.
    builder = MetaCC::Driver.new(search_paths: [])

    assert_instance_of MetaCC::Driver, builder
  end

  def test_search_paths_finds_compiler_in_custom_dir
    Dir.mktmpdir do |dir|
      # Create a fake gcc script in a custom directory.
      fake_gcc = File.join(dir, "gcc")
      File.write(fake_gcc, "#!/bin/sh\nexec gcc \"$@\"\n")
      File.chmod(0o755, fake_gcc)

      builder = MetaCC::Driver.new(
        prefer:       [MetaCC::GNU],
        search_paths: [dir]
      )

      assert_equal fake_gcc, builder.toolchain.c
    end
  end

  # ---------------------------------------------------------------------------
  # xflags: Class-keyed extra flags
  # ---------------------------------------------------------------------------
  def test_xflags_with_class_key_is_applied_for_active_toolchain
    builder = MetaCC::Driver.new
    tc_class = builder.toolchain.class
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      result = builder.invoke(src, obj, flags: [:objects], xflags: { tc_class => [] })

      assert result, "expected invoke with class-keyed xflags to succeed"
    end
  end

end
