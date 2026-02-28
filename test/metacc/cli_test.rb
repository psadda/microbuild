# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "metacc/cli"

class CLITest < Minitest::Test

  # ---------------------------------------------------------------------------
  # parse_compile_args – include paths
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_include_short
    cli = MetaCC::CLI.new
    options, sources = cli.parse_compile_args(["-I", "/usr/include", "main.c"])

    assert_equal ["/usr/include"], options[:include_paths]
    assert_equal ["main.c"], sources
  end

  def test_parse_compile_args_multiple_includes
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-I", "/a", "-I", "/b", "main.c"])

    assert_equal ["/a", "/b"], options[:include_paths]
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – definitions
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_define_short
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-D", "FOO=1", "main.c"])

    assert_equal ["FOO=1"], options[:defs]
  end

  def test_parse_compile_args_multiple_defines
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-D", "FOO", "-D", "BAR=2", "main.c"])

    assert_equal ["FOO", "BAR=2"], options[:defs]
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – output path
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_output_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-o", "out.o", "main.c"])

    assert_equal "out.o", options[:output_path]
  end

  def test_parse_compile_args_output_defaults_to_nil
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["main.c"])

    assert_nil options[:output_path]
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – RECOGNIZED_FLAGS long-form options
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_debug_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--debug", "main.c"])

    assert_includes options[:flags], :debug
  end

  def test_parse_compile_args_multiple_recognized_flags
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--pic", "--debug", "--lto", "main.c"])

    assert_includes options[:flags], :pic
    assert_includes options[:flags], :debug
    assert_includes options[:flags], :lto
  end

  def test_parse_compile_args_all_long_flag_map_flags
    cli = MetaCC::CLI.new
    MetaCC::CLI::LONG_FLAGS.each do |name, sym|
      options, _sources = cli.parse_compile_args(["--#{name}", "main.c"])

      assert_includes options[:flags], sym, "--#{name} should produce :#{sym}"
    end
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – xflags
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_xmsvc_single_value
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--xmsvc", "Z7", "main.c"])

    assert_equal ["Z7"], options[:xflags][MetaCC::MsvcToolchain]
  end

  def test_parse_compile_args_xmsvc_multiple_values
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--xmsvc", "Z7", "--xmsvc", "/EHc", "main.c"])

    assert_equal ["Z7", "/EHc"], options[:xflags][MetaCC::MsvcToolchain]
  end

  def test_parse_compile_args_xgnu_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--xgnu", "-march=skylake", "main.c"])

    assert_equal ["-march=skylake"], options[:xflags][MetaCC::GnuToolchain]
  end

  def test_parse_compile_args_xclang_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--xclang", "-fcolor-diagnostics", "main.c"])

    assert_equal ["-fcolor-diagnostics"], options[:xflags][MetaCC::ClangToolchain]
  end

  def test_parse_compile_args_xclang_cl_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--xclangcl", "/Ot", "main.c"])

    assert_equal ["/Ot"], options[:xflags][MetaCC::ClangclToolchain]
  end

  def test_parse_compile_args_mixed_xflags
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(
      ["--xmsvc", "Z7", "--xgnu", "-funroll-loops", "--xmsvc", "/EHc", "main.c"]
    )

    assert_equal ["Z7", "/EHc"], options[:xflags][MetaCC::MsvcToolchain]
    assert_equal ["-funroll-loops"], options[:xflags][MetaCC::GnuToolchain]
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – positional arguments (source files)
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_multiple_sources
    cli = MetaCC::CLI.new
    _options, sources = cli.parse_compile_args(["a.c", "b.c", "c.c"])

    assert_equal ["a.c", "b.c", "c.c"], sources
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – output type flags
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_default_has_no_output_type_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["main.c"])

    refute_includes options[:flags], :shared
    refute_includes options[:flags], :static
    refute_includes options[:flags], :objects
  end

  def test_parse_compile_args_shared_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--shared", "main.c"])

    assert_includes options[:flags], :shared
  end

  def test_parse_compile_args_static_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--static", "main.c"])

    assert_includes options[:flags], :static
  end

  def test_parse_compile_args_objects_long_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--objects", "main.c"])

    assert_includes options[:flags], :objects
  end

  def test_parse_compile_args_objects_short_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-c", "main.c"])

    assert_includes options[:flags], :objects
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – --std option (C standards for c, C++ standards for cxx)
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_lib_short_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-l", "m", "main.c"])

    assert_equal ["m"], options[:libs]
  end

  def test_parse_compile_args_libdir_short_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-L", "/usr/local/lib", "main.c"])

    assert_equal ["/usr/local/lib"], options[:linker_paths]
  end

  def test_parse_compile_args_libs_and_libdirs_default_to_empty
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["main.c"])

    assert_equal [], options[:libs]
    assert_equal [], options[:linker_paths]
  end

  def test_parse_compile_args_strip_long_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--strip", "main.c"])

    assert_includes options[:flags], :strip
  end

  def test_parse_compile_args_strip_short_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-s", "main.c"])

    assert_includes options[:flags], :strip
  end

  # ---------------------------------------------------------------------------
  # run – unknown subcommand exits
  # ---------------------------------------------------------------------------
  def test_run_unknown_subcommand_exits
    cli = MetaCC::CLI.new
    assert_raises(SystemExit) { cli.run(["unknown"]) }
  end

  def test_run_no_subcommand_exits
    cli = MetaCC::CLI.new
    assert_raises(SystemExit) { cli.run([]) }
  end

  # ---------------------------------------------------------------------------
  # run – compile/link subcommands dispatch to driver with correct arguments
  #
  # Uses a TestCLI subclass that overrides run to inject a StubDriver.
  # The StubDriver overrides only the Driver methods that call subprocesses,
  # recording their arguments so tests can assert on observable postconditions
  # without triggering real compiler invocations.
  # ---------------------------------------------------------------------------

  # A stub that records Driver#invoke calls without running subprocesses.
  class StubDriver

    class StubToolchain < MetaCC::Toolchain

      def show_version = "stubbed compiler 1.0.0\n"

    end

    attr_reader :calls, :toolchain

    def initialize
      @calls = []
      @toolchain = StubToolchain.new
    end

    def invoke(input_files, output, flags: [], xflags: {}, include_paths: [], defs: [],
               libs: [], linker_paths: [], language: :c, **)
      @calls << { method: :invoke, input_files: Array(input_files), output:, flags:, xflags:,
                  include_paths:, defs:, libs:, linker_paths:, language: }
      true
    end

  end

  # A CLI subclass that injects a StubDriver so no subprocess calls are made.
  class TestCLI < MetaCC::CLI

    attr_reader :stub_driver

    def run(argv, driver: nil)
      @stub_driver = StubDriver.new
      super(argv, driver: @stub_driver)
    end

  end

  def test_run_c_dispatches_invoke_with_output
    cli = TestCLI.new
    cli.run(["c", "-o", "main.o", "main.c"])

    call = cli.stub_driver.calls.first

    assert_equal :invoke,  call[:method]
    assert_equal "main.c", call[:input_files].first
    assert_equal "main.o", call[:output]
  end

  def test_run_c_passes_language_c
    cli = TestCLI.new
    cli.run(["c", "-o", "main.o", "main.c"])

    assert_equal :c, cli.stub_driver.calls.first[:language]
  end

  def test_run_cxx_passes_language_cxx
    cli = TestCLI.new
    cli.run(["cxx", "-o", "hello.o", "hello.cpp"])

    assert_equal :cxx, cli.stub_driver.calls.first[:language]
  end

  def test_run_cxx_dispatches_invoke
    cli = TestCLI.new
    cli.run(["cxx", "-o", "hello.o", "hello.cpp"])

    assert_equal :invoke,     cli.stub_driver.calls.first[:method]
    assert_equal "hello.cpp", cli.stub_driver.calls.first[:input_files].first
  end

  def test_run_compile_forwards_flags
    cli = TestCLI.new
    cli.run(["c", "--lto", "--debug", "-c", "-o", "main.o", "main.c"])

    flags = cli.stub_driver.calls.first[:flags]

    assert_includes flags, :lto
    assert_includes flags, :debug
    assert_includes flags, :objects
  end

  def test_run_compile_shared_flag
    cli = TestCLI.new
    cli.run(["c", "--shared", "-o", "lib.so", "main.c"])

    flags = cli.stub_driver.calls.first[:flags]

    assert_includes flags, :shared
    refute_includes flags, :objects
  end

  def test_run_compile_static_flag
    cli = TestCLI.new
    cli.run(["c", "--static", "-o", "lib.a", "main.c"])

    flags = cli.stub_driver.calls.first[:flags]

    assert_includes flags, :static
    refute_includes flags, :objects
  end

  def test_run_compile_objects_long_flag
    cli = TestCLI.new
    cli.run(["c", "--objects", "-o", "main.o", "main.c"])

    assert_includes cli.stub_driver.calls.first[:flags], :objects
  end

  def test_run_compile_objects_short_flag
    cli = TestCLI.new
    cli.run(["c", "-c", "-o", "main.o", "main.c"])

    assert_includes cli.stub_driver.calls.first[:flags], :objects
  end

  def test_run_compile_forwards_includes_and_defines
    cli = TestCLI.new
    cli.run(["c", "-I", "/inc", "-D", "FOO=1", "-o", "main.o", "main.c"])

    call = cli.stub_driver.calls.first

    assert_equal ["/inc"], call[:include_paths]
    assert_equal ["FOO=1"], call[:defs]
  end

  def test_run_compile_forwards_xflags
    cli = TestCLI.new
    cli.run(["c", "--xmsvc", "Z7", "--xmsvc", "/EHc", "-o", "main.o", "main.c"])

    xflags = cli.stub_driver.calls.first[:xflags]

    assert_equal ["Z7", "/EHc"], xflags[MetaCC::MsvcToolchain]
  end

  def test_run_compile_forwards_libs_and_linker_include_dirs
    cli = TestCLI.new
    cli.run(["c", "--shared", "-o", "lib.so", "-l", "m", "-L", "/opt/lib", "main.c"])

    call = cli.stub_driver.calls.first

    assert_equal ["m"],        call[:libs]
    assert_equal ["/opt/lib"], call[:linker_paths]
  end

end
