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
  #   --xmsvc VALUE     – appended to xflags[MsvcToolchain]
  #   --xgnu  VALUE     – appended to xflags[GnuToolchain]
  #   --xclang VALUE    – appended to xflags[ClangToolchain]
  #   --xclangcl VALUE  – appended to xflags[ClangClToolchain]
  class CLI

    # Maps long-form CLI flag names to Driver::RECOGNIZED_FLAGS symbols.
    # Optimization-level flags are handled separately via -O LEVEL.
    LONG_FLAGS = {
      "lto" =>           :lto,
      "asan" =>          :asan,
      "ubsan" =>         :ubsan,
      "msan" =>          :msan,
      "no-rtti" =>       :no_rtti,
      "no-exceptions" => :no_exceptions,
      "pic" =>           :pic
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
      "xmsvc" =>    MsvcToolchain,
      "xgnu" =>     GnuToolchain,
      "xclang" =>   ClangToolchain,
      "xclangcl" => ClangClToolchain
    }.freeze

    def self.run(argv = ARGV)
      new.run(argv)
    end

    def run(argv)
      argv = argv.dup
      subcommand = argv.shift

      case subcommand
      when "c", "cxx"
        options, sources = parse_compile_args(argv, subcommand)
        driver = build_driver
        compile_sources(driver, sources, options)
      else
        warn "Usage: metacc <c|cxx|link> [options] <files...>"
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

    def build_driver
      Driver.new
    end

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

    def compile_sources(driver, sources, options)
      sources.each do |source|
        success = driver.invoke(
          source,
          options.delete(:output_path),
          **options
        )
        exit 1 unless success
      end
    end

  end

end
