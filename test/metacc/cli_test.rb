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

    assert_equal ["/usr/include"], options[:includes]
    assert_equal ["main.c"], sources
  end

  def test_parse_compile_args_multiple_includes
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-I", "/a", "-I", "/b", "main.c"])

    assert_equal ["/a", "/b"], options[:includes]
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – definitions
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_define_short
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-D", "FOO=1", "main.c"])

    assert_equal ["FOO=1"], options[:defines]
  end

  def test_parse_compile_args_multiple_defines
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-D", "FOO", "-D", "BAR=2", "main.c"])

    assert_equal ["FOO", "BAR=2"], options[:defines]
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – output path
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_output_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-o", "out.o", "main.c"])

    assert_equal "out.o", options[:output]
  end

  def test_parse_compile_args_output_defaults_to_nil
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["main.c"])

    assert_nil options[:output]
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – optimization flags
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_O0_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-O0", "main.c"])

    assert_includes options[:flags], :o0
  end

  def test_parse_compile_args_O1_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-O1", "main.c"])

    assert_includes options[:flags], :o1
  end

  def test_parse_compile_args_O2_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-O2", "main.c"])

    assert_includes options[:flags], :o2
  end

  def test_parse_compile_args_O3_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-O3", "main.c"])

    assert_includes options[:flags], :o3
  end

  # ---------------------------------------------------------------------------
  # parse_compile_args – RECOGNIZED_FLAGS long-form options
  # ---------------------------------------------------------------------------
  def test_parse_compile_args_avx_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--avx", "main.c"])

    assert_includes options[:flags], :avx
  end

  def test_parse_compile_args_debug_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--debug", "main.c"])

    assert_includes options[:flags], :debug
  end

  def test_parse_compile_args_multiple_recognized_flags
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--avx2", "--debug", "--lto", "main.c"])

    assert_includes options[:flags], :avx2
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

    assert_equal ["/Ot"], options[:xflags][MetaCC::ClangClToolchain]
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

  def test_parse_compile_args_options_and_sources_mixed
    cli = MetaCC::CLI.new
    options, sources = cli.parse_compile_args(["-O2", "-I", "/inc", "foo.c", "bar.c"])

    assert_includes options[:flags], :o2
    assert_equal ["/inc"], options[:includes]
    assert_equal ["foo.c", "bar.c"], sources
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
  def test_parse_compile_args_c_standard_c11
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--std", "c11", "main.c"], "c")

    assert_includes options[:flags], :c11
  end

  def test_parse_compile_args_c_standard_c17
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--std", "c17", "main.c"], "c")

    assert_includes options[:flags], :c17
  end

  def test_parse_compile_args_c_standard_c23
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--std", "c23", "main.c"], "c")

    assert_includes options[:flags], :c23
  end

  def test_parse_compile_args_cxx_standard_cxx17
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--std", "c++17", "main.cpp"], "cxx")

    assert_includes options[:flags], :cxx17
  end

  def test_parse_compile_args_cxx_standard_cxx20
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--std", "c++20", "main.cpp"], "cxx")

    assert_includes options[:flags], :cxx20
  end

  def test_parse_compile_args_all_c_standards
    cli = MetaCC::CLI.new
    MetaCC::CLI::C_STANDARDS.each do |name, sym|
      options, _sources = cli.parse_compile_args(["--std", name, "main.c"], "c")

      assert_includes options[:flags], sym, "--std #{name} should produce :#{sym} for c"
    end
  end

  def test_parse_compile_args_all_cxx_standards
    cli = MetaCC::CLI.new
    MetaCC::CLI::CXX_STANDARDS.each do |name, sym|
      options, _sources = cli.parse_compile_args(["--std", name, "main.cpp"], "cxx")

      assert_includes options[:flags], sym, "--std #{name} should produce :#{sym} for cxx"
    end
  end

  def test_parse_compile_args_c_rejects_cxx_standard
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--std", "c++17", "main.c"], "c")

    refute_includes options[:flags], :cxx17
  end

  def test_parse_compile_args_cxx_rejects_c_standard
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["--std", "c11", "main.cpp"], "cxx")

    refute_includes options[:flags], :c11
  end


  def test_parse_compile_args_lib_short_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-l", "m", "main.c"])

    assert_equal ["m"], options[:libs]
  end

  def test_parse_compile_args_libdir_short_flag
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["-L", "/usr/local/lib", "main.c"])

    assert_equal ["/usr/local/lib"], options[:linker_include_dirs]
  end

  def test_parse_compile_args_libs_and_libdirs_default_to_empty
    cli = MetaCC::CLI.new
    options, _sources = cli.parse_compile_args(["main.c"])

    assert_equal [], options[:libs]
    assert_equal [], options[:linker_include_dirs]
  end

  # ---------------------------------------------------------------------------
  # parse_link_args
  # ---------------------------------------------------------------------------
  def test_parse_link_args_default_produces_no_type_flags
    cli = MetaCC::CLI.new
    options, _objects = cli.parse_link_args(["main.o"])

    assert_empty options[:flags]
  end

  def test_parse_link_args_static_flag
    cli = MetaCC::CLI.new
    options, _objects = cli.parse_link_args(["--static", "a.o", "b.o"])

    assert_equal [:static], options[:flags]
  end

  def test_parse_link_args_shared_flag
    cli = MetaCC::CLI.new
    options, _objects = cli.parse_link_args(["--shared", "util.o"])

    assert_equal [:shared], options[:flags]
  end

  def test_parse_link_args_output_flag
    cli = MetaCC::CLI.new
    options, _objects = cli.parse_link_args(["-o", "myapp", "main.o"])

    assert_equal "myapp", options[:output]
  end

  def test_parse_link_args_object_files
    cli = MetaCC::CLI.new
    _options, objects = cli.parse_link_args(["--static", "-o", "lib.a", "a.o", "b.o"])

    assert_equal ["a.o", "b.o"], objects
  end

  def test_parse_link_args_lib_short_flag
    cli = MetaCC::CLI.new
    options, _objects = cli.parse_link_args(["-l", "m", "main.o"])

    assert_equal ["m"], options[:libs]
  end

  def test_parse_link_args_multiple_libs
    cli = MetaCC::CLI.new
    options, _objects = cli.parse_link_args(["-l", "m", "-l", "pthread", "main.o"])

    assert_equal ["m", "pthread"], options[:libs]
  end

  def test_parse_link_args_libdir_short_flag
    cli = MetaCC::CLI.new
    options, _objects = cli.parse_link_args(["-L", "/usr/local/lib", "main.o"])

    assert_equal ["/usr/local/lib"], options[:linker_include_dirs]
  end

  def test_parse_link_args_libs_and_libdirs_defaults_to_empty
    cli = MetaCC::CLI.new
    options, _objects = cli.parse_link_args(["main.o"])

    assert_equal [], options[:libs]
    assert_equal [], options[:linker_include_dirs]
  end

  def test_parse_link_args_strip_long_flag
    cli = MetaCC::CLI.new
    options, _objects = cli.parse_link_args(["--strip", "main.o"])

    assert_includes options[:flags], :strip
  end

  def test_parse_link_args_strip_short_flag
    cli = MetaCC::CLI.new
    options, _objects = cli.parse_link_args(["-s", "main.o"])

    assert_includes options[:flags], :strip
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

  def test_run_version_flag_writes_version_to_stdout
    cli = TestCLI.new
    old_stdout = $stdout
    $stdout = StringIO.new
    begin
      cli.run(["--version"])
      assert_equal "stubbed compiler 1.0.0\n", $stdout.string
    ensure
      $stdout = old_stdout
    end
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

    class StubToolchain < MetaCC::Toolchain
      def show_version = "stubbed compiler 1.0.0\n"
    end

    attr_reader :calls, :toolchain

    def initialize
      @calls = []
      @toolchain = StubToolchain.new
    end

    def invoke(input_files, output, flags: [], xflags: {}, include_paths: [], definitions: [],
               libs: [], linker_include_dirs: [], **)
      @calls << { method: :invoke, input_files: Array(input_files), output:, flags:, xflags:,
                  include_paths:, definitions:, libs:, linker_include_dirs: }
      true
    end

  end

  # A CLI subclass that injects a StubDriver so no subprocess calls are made.
  class TestCLI < MetaCC::CLI

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

  def test_run_compile_defaults_to_objects_when_no_type_flag
    cli = TestCLI.new
    cli.run(["c", "-o", "main.o", "main.c"])

    assert_includes cli.stub_driver.calls.first[:flags], :objects
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
    assert_equal ["FOO=1"], call[:definitions]
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
    assert_equal ["/opt/lib"], call[:linker_include_dirs]
  end

  def test_run_compile_default_output_path
    cli = TestCLI.new
    cli.run(["c", "src/main.c"])

    assert_equal "src/main.o", cli.stub_driver.calls.first[:output]
  end

  def test_run_link_executable_dispatches_correctly
    cli = TestCLI.new
    cli.run(["link", "-o", "myapp", "a.o", "b.o"])

    call = cli.stub_driver.calls.first

    assert_equal :invoke,        call[:method]
    assert_equal ["a.o", "b.o"], call[:input_files]
    assert_equal "myapp",        call[:output]
    refute_includes call[:flags], :static
    refute_includes call[:flags], :shared
  end

  def test_run_link_static_dispatches_correctly
    cli = TestCLI.new
    cli.run(["link", "--static", "-o", "lib.a", "a.o"])

    assert_equal :invoke, cli.stub_driver.calls.first[:method]
    assert_includes cli.stub_driver.calls.first[:flags], :static
  end

  def test_run_link_shared_dispatches_correctly
    cli = TestCLI.new
    cli.run(["link", "--shared", "-o", "lib.so", "a.o"])

    assert_equal :invoke, cli.stub_driver.calls.first[:method]
    assert_includes cli.stub_driver.calls.first[:flags], :shared
  end

  def test_run_link_forwards_libs_and_linker_include_dirs
    cli = TestCLI.new
    cli.run(["link", "-o", "app", "-l", "m", "-l", "pthread", "-L", "/opt/lib", "main.o"])

    call = cli.stub_driver.calls.first

    assert_equal ["m", "pthread"], call[:libs]
    assert_equal ["/opt/lib"],     call[:linker_include_dirs]
  end

end
