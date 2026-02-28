# frozen_string_literal: true

require "optparse"
require_relative "driver"

module MetaCC

  # Command-line interface for the MetaCC Driver.
  #
  # Usage:
  #   metacc [options] <files...>
  #   metacc --version
  #
  # General:
  #   -Wall -Werror
  #   --std=c11 --std=c17 --std=c23
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
  #   -O0, -O1, -O2, -O3                           - Set the optimization level
  #   --sse4.2 --avx --avx2 --avx512 --native       - Compile for the given target
  #   --no-rtti --no-exceptions
  #   --pic
  #
  # Debugging:
  #   --debug / -g
  #   --asan --ubsan --msan
  #
  # Toolchain-specific flags (passed to Driver#invoke via xflags:):
  #   --xmsvc VALUE     – appended to xflags[MsvcToolchain]
  #   --xgnu  VALUE     – appended to xflags[GnuToolchain]
  #   --xclang VALUE    – appended to xflags[ClangToolchain]
  #   --xclangcl VALUE  – appended to xflags[ClangclToolchain]
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
    }.freeze

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
      "xclangcl" => ClangclToolchain
    }.freeze

    def run(argv, driver: Driver.new)
      argv = argv.dup
      if argv.delete("--version")
        puts driver.toolchain.show_version
        return
      end
      options, input_paths = parse_compile_args(argv)
      if input_paths.empty?
        warn "Usage: metacc [options] <files...>"
        exit 1
      end
      output_path = options.delete(:output)
      if output_path.nil? && input_paths.length == 1
        output_path = input_paths.first.sub(/\.[^.]+$/, ".o")
      end
      unless options[:flags].any? { |f| %i[shared static objects].include?(f) }
        options[:flags] << :objects
      end
      invoke(driver, input_paths, output_path, options)
    end

    # Parses compile arguments.
    # +standard_set+ selects the language-standard set: "cxx" uses CXX_STANDARDS,
    # anything else uses C_STANDARDS.
    # Returns [options_hash, remaining_positional_args].
    def parse_compile_args(argv, standard_set = "c")
      options = {
        includes: [],
        defines: [],
        linker_paths: [],
        libs: [],
        output: nil,
        flags: [],
        xflags: {},
      }
      standards = standard_set == "cxx" ? CXX_STANDARDS : C_STANDARDS
      parser = OptionParser.new
      setup_compile_options(parser, options, standards)
      sources = parser.permute(argv)
      [options, sources]
    end

    # Parses link-step arguments.
    # Returns [options_hash, remaining_positional_args (object files)].
    def parse_link_args(argv)
      options = {
        output: nil,
        flags: [],
        libs: [],
        linker_paths: [],
      }
      parser = OptionParser.new
      setup_link_options(parser, options)
      objects = parser.permute(argv)
      [options, objects]
    end

    private

    def setup_compile_options(parser, options, standards)
      parser.on("-o FILEPATH", "Output file path") do |value|
        options[:output] = value
      end
      parser.on("-I DIRPATH", "Add an include search directory") do |value|
        options[:includes] << value
      end
      parser.on("-D DEF", "Add a preprocessor definition") do |value|
        options[:defines] << value
      end
      parser.on("-O LEVEL", /\A[0-3]\z/, "Optimization level (0–3)") do |level|
        options[:flags] << :"o#{level}"
      end
      TARGETS.each do |name, sym|
        parser.on("--#{name}") do
          options[:flags] << sym
        end
      end
      parser.on("-g", "--debug", "Emit debugging symbols") do
        options[:flags] << :debug
      end
      parser.on("--std STANDARD", "Specify the language standard") do |value|
        flag = standards[value]
        options[:flags] << flag if flag
      end
      parser.on("-W OPTION", "Configure warnings") do |value|
        flag = WARNING_CONFIGS[value]
        options[:flags] << flag if flag
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

    def setup_link_options(parser, options)
      parser.on("-o FILEPATH", "Output file path") do |value|
        options[:output] = value
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
      parser.on("-l LIB", "Link against library LIB") do |value|
        options[:libs] << value
      end
      parser.on("-L DIR", "Add linker library search path") do |value|
        options[:linker_paths] << value
      end
    end

    def invoke(driver, input_paths, output_path, options)
      success = driver.invoke(
        input_paths,
        output_path,
        flags:         options[:flags],
        xflags:        options[:xflags],
        include_paths: options[:includes],
        defs:          options[:defines],
        libs:          options[:libs],
        linker_paths:  options[:linker_paths]
      )
      exit 1 unless success
    end

  end

end
