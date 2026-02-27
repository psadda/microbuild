# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "microbuild/cli"

class CLITest < Minitest::Test

  # ---------------------------------------------------------------------------
  # parse_options – pure logic
  # ---------------------------------------------------------------------------
  def test_parse_options_short_include
    includes, defines, flags, positional = cli.send(:parse_options, ["-i", "/usr/include", "src.c", "out.o"])

    assert_equal ["/usr/include"], includes
    assert_empty defines
    assert_empty flags
    assert_equal ["src.c", "out.o"], positional
  end

  def test_parse_options_long_include
    includes, _, _, _ = cli.send(:parse_options, ["--include", "/opt/include"])

    assert_equal ["/opt/include"], includes
  end

  def test_parse_options_long_include_equals
    includes, _, _, _ = cli.send(:parse_options, ["--include=/opt/include"])

    assert_equal ["/opt/include"], includes
  end

  def test_parse_options_short_define
    _, defines, _, _ = cli.send(:parse_options, ["-d", "FOO=1"])

    assert_equal ["FOO=1"], defines
  end

  def test_parse_options_long_define
    _, defines, _, _ = cli.send(:parse_options, ["--define", "BAR"])

    assert_equal ["BAR"], defines
  end

  def test_parse_options_long_define_equals
    _, defines, _, _ = cli.send(:parse_options, ["--define=BAZ=2"])

    assert_equal ["BAZ=2"], defines
  end

  def test_parse_options_flag_passthrough
    _, _, flags, _ = cli.send(:parse_options, ["-o2"])

    assert_equal [:o2], flags
  end

  def test_parse_options_flag_avx
    _, _, flags, _ = cli.send(:parse_options, ["-avx"])

    assert_equal [:avx], flags
  end

  def test_parse_options_multiple_flags
    _, _, flags, _ = cli.send(:parse_options, ["-o0", "-debug", "-lto"])

    assert_equal [:o0, :debug, :lto], flags
  end

  def test_parse_options_multiple_includes_and_defines
    includes, defines, _, _ = cli.send(
      :parse_options,
      ["-i", "/a", "--include", "/b", "-d", "X", "--define=Y=3"]
    )

    assert_equal ["/a", "/b"], includes
    assert_equal ["X", "Y=3"], defines
  end

  def test_parse_options_positional_args
    _, _, _, positional = cli.send(:parse_options, ["src.c", "out.o"])

    assert_equal ["src.c", "out.o"], positional
  end

  # ---------------------------------------------------------------------------
  # c subcommand – compile C source
  # ---------------------------------------------------------------------------
  def test_c_subcommand_compiles_and_exits_zero
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      error = assert_raises(SystemExit) { cli.run(["c", src, obj]) }

      assert_equal 0, error.status
      assert_path_exists obj
    end
  end

  def test_c_subcommand_accepts_include_and_define
    Dir.mktmpdir do |dir|
      inc = File.join(dir, "include")
      FileUtils.mkdir_p(inc)
      File.write(File.join(inc, "ver.h"), "#define VERSION 1\n")

      src = File.join(dir, "main.c")
      obj = File.join(dir, "main.o")
      File.write(src, "#include <ver.h>\nint main(void) { return VERSION - 1; }\n")

      error = assert_raises(SystemExit) do
        cli.run(["c", "-i", inc, "-d", "EXTRA=0", src, obj])
      end

      assert_equal 0, error.status
      assert_path_exists obj
    end
  end

  def test_c_subcommand_accepts_passthrough_flags
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.c")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main(void) { return 0; }\n")

      error = assert_raises(SystemExit) { cli.run(["c", "-o0", src, obj]) }

      assert_equal 0, error.status
      assert_path_exists obj
    end
  end

  def test_c_subcommand_exits_one_on_broken_source
    Dir.mktmpdir do |dir|
      src = File.join(dir, "broken.c")
      obj = File.join(dir, "broken.o")
      File.write(src, "this is not valid C code {\n")

      error = assert_raises(SystemExit) { cli.run(["c", src, obj]) }

      assert_equal 1, error.status
    end
  end

  def test_c_subcommand_exits_one_when_args_missing
    error = assert_raises(SystemExit) { cli.run(["c"]) }

    assert_equal 1, error.status
  end

  # ---------------------------------------------------------------------------
  # cxx subcommand – compile C++ source
  # ---------------------------------------------------------------------------
  def test_cxx_subcommand_compiles_and_exits_zero
    Dir.mktmpdir do |dir|
      src = File.join(dir, "hello.cpp")
      obj = File.join(dir, "hello.o")
      File.write(src, "int main() { return 0; }\n")

      error = assert_raises(SystemExit) { cli.run(["cxx", src, obj]) }

      assert_equal 0, error.status
      assert_path_exists obj
    end
  end

  # ---------------------------------------------------------------------------
  # link subcommand
  # ---------------------------------------------------------------------------
  def test_link_executable_exits_zero
    Dir.mktmpdir do |dir|
      src = File.join(dir, "main.c")
      obj = File.join(dir, "main.o")
      exe = File.join(dir, "main")
      File.write(src, "int main(void) { return 0; }\n")
      assert_raises(SystemExit) { cli.run(["c", src, obj]) }

      error = assert_raises(SystemExit) { cli.run(["link", "executable", exe, obj]) }

      assert_equal 0, error.status
      assert_path_exists exe
    end
  end

  def test_link_static_exits_zero
    Dir.mktmpdir do |dir|
      src = File.join(dir, "util.c")
      obj = File.join(dir, "util.o")
      lib = File.join(dir, "libutil.a")
      File.write(src, "int add(int a, int b) { return a + b; }\n")
      assert_raises(SystemExit) { cli.run(["c", src, obj]) }

      error = assert_raises(SystemExit) { cli.run(["link", "static", lib, obj]) }

      assert_equal 0, error.status
      assert_path_exists lib
    end
  end

  def test_link_shared_exits_zero
    Dir.mktmpdir do |dir|
      src = File.join(dir, "util.c")
      obj = File.join(dir, "util.o")
      so  = File.join(dir, "libutil.so")
      File.write(src, "int add(int a, int b) { return a + b; }\n")
      assert_raises(SystemExit) { cli.run(["c", "-pic", src, obj]) }

      error = assert_raises(SystemExit) { cli.run(["link", "shared", so, obj]) }

      assert_equal 0, error.status
      assert_path_exists so
    end
  end

  def test_link_exits_one_for_invalid_type
    error = assert_raises(SystemExit) { cli.run(["link", "bogus", "out", "obj.o"]) }

    assert_equal 1, error.status
  end

  def test_link_exits_one_when_output_missing
    error = assert_raises(SystemExit) { cli.run(["link", "executable"]) }

    assert_equal 1, error.status
  end

  def test_link_exits_one_when_objects_missing
    error = assert_raises(SystemExit) { cli.run(["link", "executable", "out"]) }

    assert_equal 1, error.status
  end

  # ---------------------------------------------------------------------------
  # unknown subcommand
  # ---------------------------------------------------------------------------
  def test_unknown_subcommand_exits_one
    error = assert_raises(SystemExit) { cli.run(["unknown"]) }

    assert_equal 1, error.status
  end

  def test_no_subcommand_exits_one
    error = assert_raises(SystemExit) { cli.run([]) }

    assert_equal 1, error.status
  end

  private

  def cli
    Microbuild::CLI.new
  end

end
