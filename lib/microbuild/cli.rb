# frozen_string_literal: true

require "optparse"
require_relative "driver"

module Microbuild

  # Command-line interface for the Microbuild Driver.
  #
  # Subcommands:
  #   c   <sources...> -o <output> [options]         – compile C source file(s)
  #   cxx <sources...> -o <output> [options]         – compile C++ source file(s)
  #   link <type> <objects...> -o <output> [options] – link object files
  #
  # <type> for the link subcommand is one of: static, shared, executable
  #
  # Recognised flags (passed to Driver#compile via flags:):
  #   -O0 -O1 -O2 -O3
  #   --sse4_2 --avx --avx2 --avx512 --native
  #   --debug --lto
  #   --warn_all --warn_error
  #   --c11 --c17 --c23
  #   --cxx11 --cxx14 --cxx17 --cxx20 --cxx23 --cxx26
  #   --asan --ubsan --msan
  #   --no_rtti --no_exceptions --pic
  #
  # Toolchain-specific flags (passed to Driver#compile via xflags:):
  #   --xmsvc VALUE     – appended to xflags[:msvc]
  #   --xgnu  VALUE     – appended to xflags[:gcc]
  #   --xclang VALUE    – appended to xflags[:clang]
  #   --xclang_cl VALUE – appended to xflags[:clang_cl]
  class CLI

    # Maps long-form CLI flag names to Driver::RECOGNIZED_FLAGS symbols.
    # Optimization-level flags are handled separately via -O LEVEL.
    LONG_FLAG_MAP = {
      "sse4_2"        => :sse4_2,
      "avx"           => :avx,
      "avx2"          => :avx2,
      "avx512"        => :avx512,
      "native"        => :native,
      "debug"         => :debug,
      "lto"           => :lto,
      "warn_all"      => :warn_all,
      "warn_error"    => :warn_error,
      "c11"           => :c11,
      "c17"           => :c17,
      "c23"           => :c23,
      "cxx11"         => :cxx11,
      "cxx14"         => :cxx14,
      "cxx17"         => :cxx17,
      "cxx20"         => :cxx20,
      "cxx23"         => :cxx23,
      "cxx26"         => :cxx26,
      "asan"          => :asan,
      "ubsan"         => :ubsan,
      "msan"          => :msan,
      "no_rtti"       => :no_rtti,
      "no_exceptions" => :no_exceptions,
      "pic"           => :pic,
    }.freeze

    # Maps --x<name> CLI option names to xflags toolchain-type keys.
    XFLAG_MAP = {
      "xmsvc"     => :msvc,
      "xgnu"      => :gcc,
      "xclang"    => :clang,
      "xclang_cl" => :clang_cl,
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
        link_type, options, objects = parse_link_args(argv)
        driver = build_driver
        link_objects(driver, link_type, objects, options[:output])
      else
        warn "Usage: microbuild <c|cxx|link> [options] <files...>"
        exit 1
      end
    end

    # Parses compile subcommand arguments.
    # Returns [options_hash, remaining_positional_args].
    def parse_compile_args(argv)
      options = { includes: [], defines: [], output: nil, flags: [], xflags: {} }

      parser = OptionParser.new do |opts|
        opts.on("-i", "--include DIR", "Add an include search directory") do |v|
          options[:includes] << v
        end
        opts.on("-d", "--define DEF", "Add a preprocessor definition") do |v|
          options[:defines] << v
        end
        opts.on("-o OUTPUT", "Output file path") do |v|
          options[:output] = v
        end
        opts.on("-O LEVEL", /\A[0-3]\z/, "Optimization level (0–3)") do |level|
          options[:flags] << :"o#{level}"
        end

        LONG_FLAG_MAP.each do |name, sym|
          opts.on("--#{name}") { options[:flags] << sym }
        end

        XFLAG_MAP.each do |name, tc_sym|
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
    # Returns [link_type_string, options_hash, remaining_positional_args].
    def parse_link_args(argv)
      argv = argv.dup
      link_type = argv.shift

      unless %w[static shared executable].include?(link_type)
        warn "Usage: microbuild link <static|shared|executable> [options] <objects...>"
        exit 1
      end

      options = { output: nil }
      parser = OptionParser.new do |opts|
        opts.on("-o OUTPUT", "Output file path") { |v| options[:output] = v }
      end
      objects = parser.parse(argv)

      [link_type, options, objects]
    end

    private

    def build_driver
      Driver.new(stdout_sink: $stdout, stderr_sink: $stderr)
    end

    def compile_sources(driver, sources, options)
      sources.each do |source|
        output = options[:output] || default_object_path(source)
        success = driver.compile(
          source, output,
          flags:         options[:flags],
          xflags:        options[:xflags],
          include_paths: options[:includes],
          definitions:   options[:defines]
        )
        exit 1 unless success
      end
    end

    def link_objects(driver, link_type, objects, output)
      success = case link_type
      when "executable" then driver.link_executable(objects, output)
      when "static"     then driver.link_static(objects, output)
      when "shared"     then driver.link_shared(objects, output)
      end
      exit 1 unless success
    end

    def default_object_path(source)
      source.sub(/\.[^.]+\z/, ".o")
    end

  end

end
