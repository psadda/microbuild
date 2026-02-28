# frozen_string_literal: true

require "optparse"
require_relative "driver"

module MetaCC

  # Command-line interface for the MetaCC Driver.
  #
  # Subcommands:
  #   c   <sources...> -o <output> [options]       – compile C source file(s)
  #   cxx <sources...> -o <output> [options]       – compile C++ source file(s)
  #   link <objects...> -o <output> [options]      – link object files (default: executable)
  #
  # Output type flags for c/cxx (default produces object files):
  #   --shared           – produce a shared library
  #   --static           – produce a static library
  #   --objects / -c     – produce object files (explicit; same as default)
  #
  # Output type flags for link (default produces an executable):
  #   --shared           – produce a shared library
  #   --static           – produce a static library
  #
  # Recognised flags (passed to Driver#compile via flags:):
  #   -O0 -O1 -O2 -O3
  #   -msse4.2 -mavx -mavx2 -mavx512 --arch=native
  #   --debug --lto
  #   -Wall -Werror
  #   --std=c11 --std=c17 --std=c23
  #   --std=c++11 --std=c++14 --std=c++17 --std=c++20 --std=c++23 --std=c++26
  #   --asan --ubsan --msan
  #   --no-rtti --no-exceptions --pic
  #
  # Toolchain-specific flags (passed to Driver#compile via xflags:):
  #   --xmsvc VALUE     – appended to xflags[:msvc]
  #   --xgnu  VALUE     – appended to xflags[:gcc]
  #   --xclang VALUE    – appended to xflags[:clang]
  #   --xclangcl VALUE  – appended to xflags[:clang_cl]
  class CLI

    # Maps long-form CLI flag names to Driver::RECOGNIZED_FLAGS symbols.
    # Optimization-level flags are handled separately via -O LEVEL.
    LONG_FLAGS = {
      "lto"           => :lto,
      "asan"          => :asan,
      "ubsan"         => :ubsan,
      "msan"          => :msan,
      "no-rtti"       => :no_rtti,
      "no-exceptions" => :no_exceptions,
      "pic"           => :pic
    }.freeze

    WARNING_CONFIGS = {
      "all"      => :warn_all,
      "error"    => :warn_error
    }

    TARGETS = {
      "sse4.2"   => :sse4_2,
      "avx"      => :avx,
      "avx2"     => :avx2,
      "avx512"   => :avx512,
      "native"   => :native
    }.freeze

    STANDARDS = {
      "c11"      => :c11,
      "c17"      => :c17,
      "c23"      => :c23,
      "c++11"    => :cxx11,
      "c++14"    => :cxx14,
      "c++17"    => :cxx17,
      "c++20"    => :cxx20,
      "c++23"    => :cxx23,
      "c++26"    => :cxx26
    }.freeze

    # Maps --x<name> CLI option names to xflags toolchain-type keys.
    XFLAGS = {
      "xmsvc"    => :msvc,
      "xgnu"     => :gcc,
      "xclang"   => :clang,
      "xclangcl" => :clang_cl
    }.freeze

    def self.run(argv = ARGV)
      new.run(argv)
    end

    def run(argv)
      argv = argv.dup
      subcommand = argv.shift

      case subcommand
      when "c", "cxx"
        options, sources = parse_compile_args(argv)
        driver = build_driver
        compile_sources(driver, sources, options)
      when "link"
        options, objects = parse_link_args(argv)
        driver = build_driver
        link_objects(driver, objects, options[:output], options[:flags], options[:libs], options[:linker_include_dirs])
      else
        warn "Usage: metacc <c|cxx|link> [options] <files...>"
        exit 1
      end
    end

    # Parses compile subcommand arguments.
    # Returns [options_hash, remaining_positional_args].
    def parse_compile_args(argv)
      options = { includes: [], defines: [], output: nil, flags: [], xflags: {} }

      parser = OptionParser.new do |opts|
        opts.on("-o FILEPATH", "Output file path") do |value|
          options[:output] = value
        end
        opts.on("-I", "--include DIRPATH", "Add an include search directory") do |value|
          options[:includes] << value
        end
        opts.on("-D", "--define DEF", "Add a preprocessor definition") do |value|
          options[:defines] << value
        end
        opts.on("-O LEVEL", /\A[0-3]\z/, "Optimization level (0–3)") do |level|
          options[:flags] << :"o#{level}"
        end
        opts.on("-m", "--arch ARCH", "Target architecture") do |value|
          options[:flags] << TARGETS[value]
        end
        opts.on("-d", "--debug", "Emit debugging symbols") do
          options[:flags] << :debug
        end
        opts.on("--std STANDARD", "Specify the language standard") do |value|
          options[:flags] << STANDARDS[value]
        end
        opts.on("-W", "--warn OPTION", "Configure warnings") do |value|
          options[:flags] << WARNING_CONFIGS[value]
        end
        opts.on("--shared", "Produce a shared library") { options[:flags] << :shared }
        opts.on("--static", "Produce a static library") { options[:flags] << :static }
        opts.on("-c", "--objects", "Produce object files") { options[:flags] << :objects }

        LONG_FLAGS.each do |name, sym|
          opts.on("--#{name}") { options[:flags] << sym }
        end

        XFLAGS.each do |name, tc_sym|
          opts.on("--#{name} VALUE", String, "Pass VALUE to the #{tc_sym} toolchain") do |v|
            options[:xflags][tc_sym] ||= []
            options[:xflags][tc_sym] << v
          end
        end
      end

      sources = parser.parse(argv)
      [options, sources]
    end

    # Parses link subcommand arguments.
    # Returns [options_hash, remaining_positional_args].
    # Output type defaults to executable; use --shared or --static to override.
    def parse_link_args(argv)
      options = { output: nil, libs: [], linker_include_dirs: [], flags: [] }
      parser = OptionParser.new do |opts|
        opts.on("-o FILEPATH", "Output file path") { |v| options[:output] = v }
        opts.on("--shared", "Produce a shared library") { options[:flags] << :shared }
        opts.on("--static", "Produce a static library") { options[:flags] << :static }
        opts.on("-l LIB", "--lib LIB", "Link against library LIB") do |v|
          options[:libs] << v
        end
        opts.on("-L DIR", "--libdir DIR", "Add linker library search path") do |v|
          options[:linker_include_dirs] << v
        end
      end
      objects = parser.parse(argv)

      [options, objects]
    end

    private

    def build_driver
      Driver.new(stdout_sink: $stdout, stderr_sink: $stderr)
    end

    OUTPUT_TYPE_FLAGS = %i[objects shared static].freeze

    def compile_sources(driver, sources, options)
      type_flags = options[:flags] & OUTPUT_TYPE_FLAGS
      type_flags = [:objects] if type_flags.empty?
      sources.each do |source|
        output = options[:output] || default_object_path(source)
        success = driver.invoke(
          source, output,
          flags:         (options[:flags] - OUTPUT_TYPE_FLAGS) + type_flags,
          xflags:        options[:xflags],
          include_paths: options[:includes],
          definitions:   options[:defines]
        )
        exit 1 unless success
      end
    end

    def link_objects(driver, objects, output, flags = [], libs = [], linker_include_dirs = [])
      success = driver.invoke(objects, output, flags:, libs:, linker_include_dirs:)
      exit 1 unless success
    end

    def default_object_path(source)
      source.sub(/\.[^.]+\z/, ".o")
    end

  end

end
