# frozen_string_literal: true

require "optparse"
require_relative "driver"

module MetaCC

  # Command-line interface for the MetaCC Driver.
  #
  # Subcommands:
  #   c   <sources...> -o <output> [options]       – compile C source file(s)
  #   cxx <sources...> -o <output> [options]       – compile C++ source file(s)
  #
  # General:
  #   -Wall -Werror
  #   --std=c11 --std=c17 --std=c23                                             (c only)
  #   --std=c++11 --std=c++14 --std=c++17 --std=c++20 --std=c++23 --std=c++26  (cxx only)
  #
  # Linking:
  #   --objects / -c     – compile only; don't link
  #   -l, -L             - specify linker input
  #   --shared           – produce a shared library
  #   --static           – produce a static library
  #   --lto              - enable link time optimization
  #   --strip / -s       – strip unneeded symbols
  #
  # Code generation:
  #   -O0, -O1, -O2, -O3                             - Set the optimization level
  #   -msse4.2 -mavx -mavx2 -mavx512 --arch=native   - Compile for the given target
  #   --no-rtti --no-exceptions
  #   --pic
  #
  # Debugging:
  #   --debug / -g
  #   --asan --ubsan --msan
  #
  # Toolchain-specific flags (passed to Driver#compile via xflags:):
  #   --xmsvc VALUE     – appended to xflags[MSVC]
  #   --xgnu  VALUE     – appended to xflags[GNU]
  #   --xclang VALUE    – appended to xflags[Clang]
  #   --xclangcl VALUE  – appended to xflags[ClangCL]
  class CLI

    # Maps long-form CLI flag names to Driver::RECOGNIZED_FLAGS symbols.
    # Optimization-level flags are handled separately via -O LEVEL.
    LONG_FLAGS = {
      "lto" =>                       :lto,
      "asan" =>                      :asan,
      "ubsan" =>                     :ubsan,
      "msan" =>                      :msan,
      "no-rtti" =>                   :no_rtti,
      "no-exceptions" =>             :no_exceptions,
      "pic" =>                       :pic,
      "no-semantic-interposition" => :no_semantic_interposition,
      "no-omit-frame-pointer" =>     :no_omit_frame_pointer,
      "no-strict-aliasing" =>        :no_strict_aliasing
    }.freeze

    WARNING_CONFIGS = {
      "all" =>   :warn_all,
      "error" => :warn_error
    }

    TARGETS = {
      "sse4.2" => :sse4_2,
      "avx" =>    :avx,
      "avx2" =>   :avx2,
      "avx512" => :avx512,
      "native" => :native
    }.freeze

    C_STANDARDS = {
      "c11" => :c11,
      "c17" => :c17,
      "c23" => :c23
    }.freeze

    CXX_STANDARDS = {
      "c++11" => :cxx11,
      "c++14" => :cxx14,
      "c++17" => :cxx17,
      "c++20" => :cxx20,
      "c++23" => :cxx23,
      "c++26" => :cxx26
    }.freeze

    # Maps --x<name> CLI option names to xflags toolchain-class keys.
    XFLAGS = {
      "xmsvc" =>    MSVC,
      "xgnu" =>     GNU,
      "xclang" =>   Clang,
      "xclangcl" => ClangCL
    }.freeze

    def run(argv, driver: Driver.new)
      argv = argv.dup
      subcommand = argv.shift

      case subcommand
      when "c", "cxx"
        options, input_paths = parse_compile_args(argv, subcommand)
        output_path = options.delete(:output_path)
        run_flag = options.delete(:run)
        language = subcommand == "cxx" ? :cxx : :c
        validate_options!(options[:flags], output_path, run_flag)
        invoke(driver, input_paths, output_path, options, language:, run: run_flag)
      else
        warn "Usage: metacc <c|cxx> [options] <files...>"
        exit 1
      end
    end

    # Parses compile subcommand arguments.
    # Returns [options_hash, remaining_positional_args].
    def parse_compile_args(argv, subcommand = "c")
      options = {
        include_paths: [],
        defs: [],
        linker_paths: [],
        libs: [],
        output_path: nil,
        run: false,
        flags: [],
        xflags: {},
      }
      standards = subcommand == "cxx" ? CXX_STANDARDS : C_STANDARDS
      parser = OptionParser.new
      setup_compile_options(parser, options, standards)
      sources = parser.permute(argv)
      [options, sources]
    end

    private

    def setup_compile_options(parser, options, standards)
      parser.on("-o FILEPATH", "Output file path") do |value|
        options[:output_path] = value
      end
      parser.on("-I DIRPATH", "Add an include search directory") do |value|
        options[:include_paths] << value
      end
      parser.on("-D DEF", "Add a preprocessor definition") do |value|
        options[:defs] << value
      end
      parser.on("-O LEVEL", /\A[0-3]\z/, "Optimization level (0–3)") do |level|
        options[:flags] << :"o#{l}"
      end
      parser.on("-Os", "Optimize for size") do
        options[:flags] << :os
      end
      parser.on("-m", "--arch ARCH", "Target architecture") do |value|
        options[:flags] << TARGETS[v]
      end
      parser.on("-g", "--debug", "Emit debugging symbols") do
        options[:flags] << :debug
      end
      parser.on("--std STANDARD", "Specify the language standard") do |value|
        options[:flags] << standards[v]
      end
      parser.on("-W OPTION", "Configure warnings") do |value|
        options[:flags] << WARNING_CONFIGS[v]
      end
      parser.on("-c", "--objects", "Produce object files") do
        options[:flags] << :objects
      end
      parser.on("-r", "--run", "Run the compiled executable after a successful build") do
        options[:run] = true
      end
      parser.on("-l LIB", "Link against library LIB") do |value|
        options[:libs] << value
      end
      parser.on("-L DIR", "Add linker library search path") do |value|
        options[:linker_paths] << value
      end
      parser.on("--shared", "Produce a shared library") do
        options[:flags] << :shared
      end
      parser.on("--static", "Produce a static library") do
        options[:flags] << :static
      end
      parser.on("-s", "--strip", "Strip unneeded symbols") do
        options[:flags] << :strip
      end
      LONG_FLAGS.each do |name, sym|
        parser.on("--#{name}") do
          options[:flags] << sym
        end
      end
      XFLAGS.each do |name, tc_class|
        parser.on("--#{name} VALUE", "Pass VALUE to the #{tc_class} toolchain") do |value|
          options[:xflags][tc_class] ||= []
          options[:xflags][tc_class] << value
        end
      end
    end

    def validate_options!(flags, output_path, run_flag)
      objects = flags.include?(:objects)

      if objects && output_path
        warn "error: -o cannot be used with --objects"
        exit 1
      end

      unless objects || output_path
        warn "error: -o is required"
        exit 1
      end

      if run_flag && (objects || flags.include?(:shared) || flags.include?(:static))
        warn "error: --run cannot be used with --objects, --shared, or --static"
        exit 1
      end
    end

    def run_executable(path)
      system(path)
    end

    def invoke(driver, input_paths, output_path, options, language: :c, run: false)
      result = driver.invoke(input_paths, output_path, language:, **options)
      exit 1 unless result
      run_executable(result) if run
    end

  end

end
