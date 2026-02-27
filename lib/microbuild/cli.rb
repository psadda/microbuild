# frozen_string_literal: true

require_relative "driver"

module Microbuild

  # Command-line interface for the Driver.
  #
  # Subcommands:
  #   c   <source> <output> [options]  – compile a C source file
  #   cxx <source> <output> [options]  – compile a C++ source file
  #   link <type> <output> <obj...>    – link object files (type: static|shared|executable)
  #
  # Shared options (c / cxx):
  #   -i PATH, --include PATH   add an include directory (repeatable)
  #   -d DEF,  --define  DEF    add a preprocessor definition (repeatable)
  #   -FLAG                     pass FLAG as a driver flag symbol (e.g. -o0, -avx)
  class CLI

    def run(argv)
      argv = argv.dup
      subcommand = argv.shift
      case subcommand
      when "c", "cxx"
        run_compile(argv)
      when "link"
        run_link(argv)
      else
        $stderr.puts "Usage: microbuild (c|cxx|link) [options] ..."
        exit 1
      end
    end

    private

    def run_compile(argv)
      includes, defines, flags, positional = parse_options(argv)
      source, output = positional
      unless source && output
        $stderr.puts "Usage: microbuild (c|cxx) [-i DIR] [-d DEF] [-FLAG ...] <source_file> <output_file>"
        exit 1
      end
      success = build_driver.compile(source, output, flags:, include_paths: includes, definitions: defines)
      exit(success ? 0 : 1)
    end

    def run_link(argv)
      type = argv.shift
      unless %w[static shared executable].include?(type)
        $stderr.puts "Usage: microbuild link (static|shared|executable) <output_file> <object_file...>"
        exit 1
      end
      _, _, _, positional = parse_options(argv)
      output = positional.shift
      objects = positional
      if output.nil? || objects.empty?
        $stderr.puts "Usage: microbuild link #{type} <output_file> <object_file...>"
        exit 1
      end
      driver = build_driver
      success = case type
                when "static"     then driver.link_static(objects, output)
                when "shared"     then driver.link_shared(objects, output)
                when "executable" then driver.link_executable(objects, output)
                end
      exit(success ? 0 : 1)
    end

    # Parses an argument list, returning [includes, defines, flags, positional].
    #
    # -i PATH / --include PATH / --include=PATH  → include path
    # -d DEF  / --define  DEF  / --define=DEF    → preprocessor definition
    # -FLAG                                       → flag symbol (e.g. -o0 → :o0)
    # everything else                             → positional argument
    def parse_options(argv)
      includes  = []
      defines   = []
      flags     = []
      positional = []
      i = 0
      while i < argv.length
        arg = argv[i]
        if arg == "-i" || arg == "--include"
          i += 1
          includes << argv[i]
        elsif (m = arg.match(/\A--include=(.*)\z/))
          includes << m[1]
        elsif arg == "-d" || arg == "--define"
          i += 1
          defines << argv[i]
        elsif (m = arg.match(/\A--define=(.*)\z/))
          defines << m[1]
        elsif arg.start_with?("-")
          flags << arg.sub(/\A-+/, "").to_sym
        else
          positional << arg
        end
        i += 1
      end
      [includes, defines, flags, positional]
    end

    def build_driver
      Driver.new(stdout_sink: $stdout, stderr_sink: $stderr)
    end

  end

end
