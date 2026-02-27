# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "microbuild/cli"

class CLITest < Minitest::Test

  # ---------------------------------------------------------------------------
  # parse_compile_args – include paths
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_include_short
    cli = Microbuild::CLI.new
    options, sources = cli.parse_compile_args(["-i", "/usr/include", "main.c"])

    assert_equal ["/usr/include"], options[:includes]
    assert_equal ["main.c"], sources
  end

  def test_parse_compile_args_include_long
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["--include", "/opt/include", "main.c"])

    assert_equal ["/opt/include"], options[:includes]
  end

  def test_parse_compile_args_multiple_includes
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["-i", "/a", "-i", "/b", "main.c"])

    assert_equal ["/a", "/b"], options[:includes]
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – definitions
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_define_short
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["-d", "FOO=1", "main.c"])

    assert_equal ["FOO=1"], options[:defines]
  end

  def test_parse_compile_args_define_long
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["--define", "BAR", "main.c"])

    assert_equal ["BAR"], options[:defines]
  end

  def test_parse_compile_args_multiple_defines
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["-d", "FOO", "-d", "BAR=2", "main.c"])

    assert_equal ["FOO", "BAR=2"], options[:defines]
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – output path
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_output_flag
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["-o", "out.o", "main.c"])

    assert_equal "out.o", options[:output]
  end

  def test_parse_compile_args_output_defaults_to_nil
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["main.c"])

    assert_nil options[:output]
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – optimization flags
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_O0_flag
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["-O0", "main.c"])

    assert_includes options[:flags], :o0
  end

  def test_parse_compile_args_O1_flag
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["-O1", "main.c"])

    assert_includes options[:flags], :o1
  end

  def test_parse_compile_args_O2_flag
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["-O2", "main.c"])

    assert_includes options[:flags], :o2
  end

  def test_parse_compile_args_O3_flag
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["-O3", "main.c"])

    assert_includes options[:flags], :o3
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – RECOGNIZED_FLAGS long-form options
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_avx_flag
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["--avx", "main.c"])

    assert_includes options[:flags], :avx
  end

  def test_parse_compile_args_debug_flag
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["--debug", "main.c"])

    assert_includes options[:flags], :debug
  end

  def test_parse_compile_args_multiple_recognized_flags
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["--avx2", "--debug", "--lto", "main.c"])

    assert_includes options[:flags], :avx2
    assert_includes options[:flags], :debug
    assert_includes options[:flags], :lto
  end

  def test_parse_compile_args_all_long_flag_map_flags
    cli = Microbuild::CLI.new
    Microbuild::CLI::LONG_FLAG_MAP.each do |name, sym|
      options, _sources = cli.parse_compile_args(["--#{name}", "main.c"])

      assert_includes options[:flags], sym, "--#{name} should produce :#{sym}"
    end
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – xflags
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_xmsvc_single_value
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["--xmsvc", "Z7", "main.c"])

    assert_equal ["Z7"], options[:xflags][:msvc]
  end

  def test_parse_compile_args_xmsvc_multiple_values
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["--xmsvc", "Z7", "--xmsvc", "/EHc", "main.c"])

    assert_equal ["Z7", "/EHc"], options[:xflags][:msvc]
  end

  def test_parse_compile_args_xgnu_flag
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["--xgnu", "-march=skylake", "main.c"])

    assert_equal ["-march=skylake"], options[:xflags][:gcc]
  end

  def test_parse_compile_args_xclang_flag
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["--xclang", "-fcolor-diagnostics", "main.c"])

    assert_equal ["-fcolor-diagnostics"], options[:xflags][:clang]
  end

  def test_parse_compile_args_xclang_cl_flag
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(["--xclang_cl", "/Ot", "main.c"])

    assert_equal ["/Ot"], options[:xflags][:clang_cl]
  end

  def test_parse_compile_args_mixed_xflags
    cli = Microbuild::CLI.new
    options, _sources = cli.parse_compile_args(
      ["--xmsvc", "Z7", "--xgnu", "-funroll-loops", "--xmsvc", "/EHc", "main.c"]
    )

    assert_equal ["Z7", "/EHc"], options[:xflags][:msvc]
    assert_equal ["-funroll-loops"], options[:xflags][:gcc]
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – positional arguments (source files)
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_multiple_sources
    cli = Microbuild::CLI.new
    _options, sources = cli.parse_compile_args(["a.c", "b.c", "c.c"])

    assert_equal ["a.c", "b.c", "c.c"], sources
  end

  def test_parse_compile_args_options_and_sources_mixed
    cli = Microbuild::CLI.new
    options, sources = cli.parse_compile_args(["-O2", "-i", "/inc", "foo.c", "bar.c"])

    assert_includes options[:flags], :o2
    assert_equal ["/inc"], options[:includes]
    assert_equal ["foo.c", "bar.c"], sources
  end

  # ---------------------------------------------------------------------------
  # parse_link_args
  # ---------------------------------------------------------------------------
  def test_parse_link_args_executable_type
    cli = Microbuild::CLI.new
    link_type, _options, _objects = cli.parse_link_args(["executable", "main.o"])

    assert_equal "executable", link_type
  end

  def test_parse_link_args_static_type
    cli = Microbuild::CLI.new
    link_type, _options, _objects = cli.parse_link_args(["static", "a.o", "b.o"])

    assert_equal "static", link_type
  end

  def test_parse_link_args_shared_type
    cli = Microbuild::CLI.new
    link_type, _options, _objects = cli.parse_link_args(["shared", "util.o"])

    assert_equal "shared", link_type
  end

  def test_parse_link_args_output_flag
    cli = Microbuild::CLI.new
    _link_type, options, _objects = cli.parse_link_args(["executable", "-o", "myapp", "main.o"])

    assert_equal "myapp", options[:output]
  end

  def test_parse_link_args_object_files
    cli = Microbuild::CLI.new
    _link_type, _options, objects = cli.parse_link_args(["static", "-o", "lib.a", "a.o", "b.o"])

    assert_equal ["a.o", "b.o"], objects
  end

  def test_parse_link_args_invalid_type_exits
    cli = Microbuild::CLI.new
    assert_raises(SystemExit) do
      cli.parse_link_args(["bogus", "main.o"])
    end
  end

  # ---------------------------------------------------------------------------
  # run – unknown subcommand exits
  # ---------------------------------------------------------------------------
  def test_run_unknown_subcommand_exits
    cli = Microbuild::CLI.new
    assert_raises(SystemExit) { cli.run(["unknown"]) }
  end

  def test_run_no_subcommand_exits
    cli = Microbuild::CLI.new
    assert_raises(SystemExit) { cli.run([]) }
  end

  # ---------------------------------------------------------------------------
  # run – compile/link subcommands dispatch to driver with correct arguments
  #
  # Uses a TestCLI subclass that overrides build_driver to return a StubDriver.
  # The StubDriver overrides only the Driver methods that call subprocesses,
  # recording their arguments so tests can assert on observable postconditions
  # without triggering real compiler invocations.
  # ---------------------------------------------------------------------------

  # A stub that records Driver#invoke calls without running subprocesses.
  class StubDriver

    attr_reader :calls

    def initialize
      @calls = []
    end

    def invoke(input_files, output, flags: [], xflags: {}, include_paths: [], definitions: [], **)
      @calls << { method: :invoke, input_files: Array(input_files), output:, flags:, xflags:,
                  include_paths:, definitions: }
      true
    end

  end

  # A CLI subclass that injects a StubDriver so no subprocess calls are made.
  class TestCLI < Microbuild::CLI

    attr_reader :stub_driver

    private

    def build_driver
      @stub_driver = StubDriver.new
    end

  end

  def test_run_c_dispatches_invoke_with_output
    cli = TestCLI.new
    cli.run(["c", "-o", "main.o", "main.c"])

    call = cli.stub_driver.calls.first

    assert_equal :invoke,  call[:method]
    assert_equal "main.c", call[:input_files].first
    assert_equal "main.o", call[:output]
    assert_includes call[:flags], :objects
  end

  def test_run_cxx_dispatches_invoke
    cli = TestCLI.new
    cli.run(["cxx", "-o", "hello.o", "hello.cpp"])

    assert_equal :invoke,     cli.stub_driver.calls.first[:method]
    assert_equal "hello.cpp", cli.stub_driver.calls.first[:input_files].first
  end

  def test_run_compile_forwards_flags
    cli = TestCLI.new
    cli.run(["c", "-O2", "--avx", "--debug", "-o", "main.o", "main.c"])

    flags = cli.stub_driver.calls.first[:flags]

    assert_includes flags, :o2
    assert_includes flags, :avx
    assert_includes flags, :debug
    assert_includes flags, :objects
  end

  def test_run_compile_forwards_includes_and_defines
    cli = TestCLI.new
    cli.run(["c", "-i", "/inc", "-d", "FOO=1", "-o", "main.o", "main.c"])

    call = cli.stub_driver.calls.first

    assert_equal ["/inc"], call[:include_paths]
    assert_equal ["FOO=1"], call[:definitions]
  end

  def test_run_compile_forwards_xflags
    cli = TestCLI.new
    cli.run(["c", "--xmsvc", "Z7", "--xmsvc", "/EHc", "-o", "main.o", "main.c"])

    xflags = cli.stub_driver.calls.first[:xflags]

    assert_equal ["Z7", "/EHc"], xflags[:msvc]
  end

  def test_run_compile_default_output_path
    cli = TestCLI.new
    cli.run(["c", "src/main.c"])

    assert_equal "src/main.o", cli.stub_driver.calls.first[:output]
  end

  def test_run_link_executable_dispatches_correctly
    cli = TestCLI.new
    cli.run(["link", "executable", "-o", "myapp", "a.o", "b.o"])

    call = cli.stub_driver.calls.first

    assert_equal :invoke,        call[:method]
    assert_equal ["a.o", "b.o"], call[:input_files]
    assert_equal "myapp",        call[:output]
    refute_includes call[:flags], :static
    refute_includes call[:flags], :shared
  end

  def test_run_link_static_dispatches_correctly
    cli = TestCLI.new
    cli.run(["link", "static", "-o", "lib.a", "a.o"])

    assert_equal :invoke, cli.stub_driver.calls.first[:method]
    assert_includes cli.stub_driver.calls.first[:flags], :static
  end

  def test_run_link_shared_dispatches_correctly
    cli = TestCLI.new
    cli.run(["link", "shared", "-o", "lib.so", "a.o"])

    assert_equal :invoke, cli.stub_driver.calls.first[:method]
    assert_includes cli.stub_driver.calls.first[:flags], :shared
  end

end
