require "open3"

module Microbuild
  # Raised when no supported C/C++ compiler can be found on the system.
  class CompilerNotFoundError < StandardError; end

  # Builder wraps C and C++ compile and link operations using the first
  # available compiler found on the system (Clang, GCC, or MSVC).
  class Builder
    # Ordered list of compiler candidates to probe.  Each entry is a Hash with:
    #   :c   – command used to compile C source files
    #   :cxx – command used to compile C++ source files
    #   :ld  – command used to link object files
    #   :type – symbolic name for the toolchain
    COMPILER_CANDIDATES = [
      { type: :clang, c: "clang",   cxx: "clang++", ld: "clang++" },
      { type: :gcc,   c: "gcc",     cxx: "g++",     ld: "g++"     },
      { type: :msvc,  c: "cl",      cxx: "cl",      ld: "link"    },
    ].freeze

    # The detected toolchain Hash (see COMPILER_CANDIDATES).
    attr_reader :compiler

    # Detects the first available C/C++ compiler toolchain.
    #
    # @raise [CompilerNotFoundError] if no supported compiler is found.
    def initialize
      @compiler = detect_compiler!
    end

    # Compiles a single source file into an object file.
    #
    # @param source_file_path [String] path to the .c or .cpp source file
    # @param output_path      [String] path for the resulting object file
    # @param flags            [Array<String>] extra compiler flags
    # @param include_paths    [Array<String>] directories to add with -I
    # @param definitions      [Array<String>] preprocessor macros (e.g. "FOO" or "FOO=1")
    # @return [Boolean] true if compilation succeeded, false otherwise
    def compile(source_file_path, output_path, flags: [], include_paths: [], definitions: [])
      cmd = build_compile_command(source_file_path, output_path, flags, include_paths, definitions)
      run_command(cmd)
    end

    # Links one or more object files into an executable or shared library.
    #
    # @param object_file_paths [Array<String>] paths to the object files to link
    # @param output_path       [String] path for the resulting binary
    # @return [Boolean] true if linking succeeded, false otherwise
    def link(object_file_paths, output_path)
      cmd = build_link_command(object_file_paths, output_path)
      run_command(cmd)
    end

    private

    def detect_compiler!
      COMPILER_CANDIDATES.each do |candidate|
        return candidate if compiler_available?(candidate[:c])
      end
      raise CompilerNotFoundError, "No supported C/C++ compiler found (tried clang, gcc, cl)"
    end

    def compiler_available?(command)
      _out, _err, status = Open3.capture3(command, "--version")
      status.success?
    rescue Errno::ENOENT
      false
    end

    def c_file?(path)
      File.extname(path).downcase == ".c"
    end

    def build_compile_command(source, output, flags, include_paths, definitions)
      if compiler[:type] == :msvc
        build_msvc_compile_command(source, output, flags, include_paths, definitions)
      else
        cc = c_file?(source) ? compiler[:c] : compiler[:cxx]
        inc_flags = include_paths.map { |p| "-I#{p}" }
        def_flags = definitions.map  { |d| "-D#{d}" }
        [cc, *flags, *inc_flags, *def_flags, "-c", source, "-o", output]
      end
    end

    def build_msvc_compile_command(source, output, flags, include_paths, definitions)
      inc_flags = include_paths.map { |p| "/I#{p}" }
      def_flags = definitions.map  { |d| "/D#{d}" }
      [compiler[:c], *flags, *inc_flags, *def_flags, "/c", source, "/Fo#{output}"]
    end

    def build_link_command(object_files, output)
      if compiler[:type] == :msvc
        [compiler[:ld], *object_files, "/OUT:#{output}"]
      else
        [compiler[:ld], *object_files, "-o", output]
      end
    end

    def run_command(cmd)
      _out, _err, status = Open3.capture3(*cmd)
      status.success?
    end
  end
end
