require "open3"

module Microbuild
  # Raised when no supported C/C++ compiler can be found on the system.
  class CompilerNotFoundError < StandardError; end

  # Holds information about a detected compiler toolchain.
  #   type   – symbolic name (:clang, :gcc, :msvc)
  #   c      – command used to compile C source files
  #   cxx    – command used to compile C++ source files
  #   ld     – command used to link executables and shared libraries
  #   ar     – command used to create static libraries (nil if not found)
  #   ranlib – command used to index static libraries (nil if not found)
  CompilerInfo = Struct.new(:type, :c, :cxx, :ld, :ar, :ranlib)

  # Builder wraps C and C++ compile and link operations using the first
  # available compiler found on the system (Clang, GCC, or MSVC).
  class Builder
    # Ordered list of compiler candidates to probe.
    COMPILER_CANDIDATES = [
      { type: :clang, c: "clang", cxx: "clang++", ld: "clang++", ar: "ar",  ranlib: "ranlib" },
      { type: :gcc,   c: "gcc",   cxx: "g++",     ld: "g++",     ar: "ar",  ranlib: "ranlib" },
      { type: :msvc,  c: "cl",    cxx: "cl",       ld: "link",    ar: "lib", ranlib: nil      },
    ].freeze

    # The detected toolchain (a CompilerInfo struct).
    attr_reader :compiler

    # Accumulated log entries from all compile/link invocations.
    # Each entry is a Hash with :command, :stdout, and :stderr keys.
    attr_reader :log

    # Detects the first available C/C++ compiler toolchain.
    #
    # @param stdout_sink [#write, nil] optional object whose +write+ method is called
    #                                 with each command's stdout after every invocation.
    # @param stderr_sink [#write, nil] optional object whose +write+ method is called
    #                                 with each command's stderr after every invocation.
    #                                 The same object may be passed for both sinks.
    # @raise [CompilerNotFoundError] if no supported compiler is found.
    def initialize(stdout_sink: nil, stderr_sink: nil)
      @stdout_sink = stdout_sink
      @stderr_sink = stderr_sink
      @log = []
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

    # Links one or more object files into an executable.
    #
    # @param object_file_paths [Array<String>] paths to the object files to link
    # @param output_path       [String] path for the resulting executable
    # @return [Boolean] true if linking succeeded, false otherwise
    def link_executable(object_file_paths, output_path)
      run_command(build_link_executable_command(object_file_paths, output_path))
    end

    # Archives one or more object files into a static library.
    # Uses +ar rcs+ on Unix (plus +ranlib+ if detected) and +lib+ on MSVC.
    # Returns false if the archiver (+ar+ / +lib+) is not available.
    #
    # @param object_file_paths [Array<String>] paths to the object files
    # @param output_path       [String] path for the resulting static library
    # @return [Boolean] true if archiving succeeded, false otherwise
    def link_static(object_file_paths, output_path)
      return false unless compiler.ar

      if compiler.type == :msvc
        run_command([compiler.ar, "/OUT:#{output_path}", *object_file_paths])
      else
        return false unless run_command([compiler.ar, "rcs", output_path, *object_file_paths])
        return run_command([compiler.ranlib, output_path]) if compiler.ranlib
        true
      end
    end

    # Links one or more object files into a shared library.
    #
    # @param object_file_paths [Array<String>] paths to the object files to link
    # @param output_path       [String] path for the resulting shared library
    # @return [Boolean] true if linking succeeded, false otherwise
    def link_shared(object_file_paths, output_path)
      run_command(build_link_shared_command(object_file_paths, output_path))
    end

    private

    def detect_compiler!
      COMPILER_CANDIDATES.each do |candidate|
        next unless command_available?(candidate[:c])
        ar     = candidate[:ar]     if command_available?(candidate[:ar])
        ranlib = candidate[:ranlib] if command_available?(candidate[:ranlib])
        return CompilerInfo.new(candidate[:type], candidate[:c], candidate[:cxx],
                                candidate[:ld], ar, ranlib)
      end
      raise CompilerNotFoundError, "No supported C/C++ compiler found (tried clang, gcc, cl)"
    end

    # Returns true if +command+ is present in PATH, false otherwise.
    # Intentionally ignores the exit status – only ENOENT (not found) matters.
    def command_available?(command)
      return false if command.nil?
      Open3.capture3(command, "--version")
      true
    rescue Errno::ENOENT
      false
    end

    def c_file?(path)
      File.extname(path).downcase == ".c"
    end

    def build_compile_command(source, output, flags, include_paths, definitions)
      if compiler.type == :msvc
        build_msvc_compile_command(source, output, flags, include_paths, definitions)
      else
        cc = c_file?(source) ? compiler.c : compiler.cxx
        inc_flags = include_paths.map { |p| "-I#{p}" }
        def_flags = definitions.map  { |d| "-D#{d}" }
        [cc, *flags, *inc_flags, *def_flags, "-c", source, "-o", output]
      end
    end

    def build_msvc_compile_command(source, output, flags, include_paths, definitions)
      inc_flags = include_paths.map { |p| "/I#{p}" }
      def_flags = definitions.map  { |d| "/D#{d}" }
      [compiler.c, *flags, *inc_flags, *def_flags, "/c", source, "/Fo#{output}"]
    end

    def build_link_executable_command(object_files, output)
      if compiler.type == :msvc
        [compiler.ld, *object_files, "/OUT:#{output}"]
      else
        [compiler.ld, *object_files, "-o", output]
      end
    end

    def build_link_shared_command(object_files, output)
      if compiler.type == :msvc
        [compiler.ld, "/DLL", *object_files, "/OUT:#{output}"]
      else
        [compiler.ld, "-shared", *object_files, "-o", output]
      end
    end

    def run_command(cmd)
      out, err, status = Open3.capture3(*cmd)
      record_output(cmd, out, err)
      status.success?
    end

    def record_output(command, stdout, stderr)
      entry = { command: command, stdout: stdout, stderr: stderr }
      @log << entry
      @stdout_sink.write(stdout) if @stdout_sink.respond_to?(:write)
      @stderr_sink.write(stderr) if @stderr_sink.respond_to?(:write)
    end
  end
end
