# frozen_string_literal: true

require "open3"
require_relative "toolchain"

module MetaCC

  # Raised when no supported C/C++ compiler can be found on the system.
  class CompilerNotFoundError < StandardError; end

  # Driver wraps C and C++ compile and link operations using the first
  # available compiler found on the system (Clang, GCC, or MSVC).
  class Driver

    # Ordered list of toolchain classes to probe, in priority order.
    TOOLCHAIN_CLASSES = [ClangToolchain, GnuToolchain, MsvcToolchain].freeze

    RECOGNIZED_FLAGS = Set.new(
      %i[
        o0 o1 o2 o3
        sse4_2 avx avx2 avx512 native
        debug lto
        warn_all warn_error
        c11 c17 c23
        cxx11 cxx14 cxx17 cxx20 cxx23 cxx26
        asan ubsan msan
        no_rtti no_exceptions pic
        objects shared static strip
      ]
    ).freeze

    # The detected toolchain (a Toolchain subclass instance).
    attr_reader :toolchain

    # Accumulated log entries from all invoke invocations.
    # Each entry is a Hash with :command, :stdout, and :stderr keys.
    attr_reader :log

    # The directory used to resolve relative output file paths.
    attr_reader :output_dir

    # Detects the first available C/C++ compiler toolchain.
    #
    # @param stdout_sink [#write, nil] optional object whose +write+ method is called
    #                                 with each command's stdout after every invocation.
    # @param stderr_sink [#write, nil] optional object whose +write+ method is called
    #                                 with each command's stderr after every invocation.
    #                                 The same object may be passed for both sinks.
    # @param output_dir  [String] directory prepended to relative output file paths
    #                            (default: "build"). Absolute output paths are used as-is.
    # @raise [CompilerNotFoundError] if no supported compiler is found.
    def initialize(stdout_sink: nil, stderr_sink: nil, output_dir: "build")
      @stdout_sink = stdout_sink
      @stderr_sink = stderr_sink
      @output_dir = output_dir
      @log = []
      @toolchain = detect_toolchain!
    end

    # Invokes the compiler driver for the given input files and output path.
    # The kind of output (object files, executable, shared library, or static
    # library) is determined by the flags: +:objects+, +:shared+, or +:static+.
    # When none of these mode flags is present, an executable is produced.
    #
    # Skips the invocation if +output_path+ already exists and is newer than all
    # +input_files+. Pass <tt>force: true</tt> to always re-invoke.
    # Relative +output_path+ values are resolved under +output_dir+.
    #
    # @param input_files          [String, Array<String>] paths to the input files
    # @param output_path          [String] path for the resulting output file
    # @param flags                [Array<Symbol>] compiler/linker flags
    # @param xflags               [Hash{Symbol => String}] extra (native) compiler flags
    # @param include_paths        [Array<String>] directories to add with -I
    # @param definitions          [Array<String>] preprocessor macros (e.g. "FOO" or "FOO=1")
    # @param libs                 [Array<String>] library names to link (e.g. "m", "pthread")
    # @param linker_include_dirs  [Array<String>] linker library search paths (-L / /LIBPATH:)
    # @param force                [Boolean] when true, always invoke even if output is up-to-date
    # @param env                  [Hash] environment variables to set for the subprocess
    # @param working_dir          [String] working directory for the subprocess (default: ".")
    # @return [Boolean] true if invocation succeeded (or was skipped), false otherwise
    def invoke(
      input_files,
      output_path,
      flags: [],
      xflags: {},
      include_paths: [],
      definitions: [],
      libs: [],
      linker_include_dirs: [],
      force: false,
      env: {},
      working_dir: "."
    )
      input_files = Array(input_files)
      flags = translate_flags(flags)
      flags.concat(xflags[@toolchain.type] || [])

      out = resolve_output(output_path)
      return true if !force && up_to_date?(out, input_files)

      cmd = @toolchain.command(input_files, out, flags, include_paths, definitions, libs, linker_include_dirs)
      run_command(cmd, env:, working_dir:)
    end

    # Returns the version string reported by the detected compiler toolchain.
    def show_version
      @toolchain.show_version
    end

    private

    def detect_toolchain!
      toolchain_classes.each do |klass|
        tc = klass.new
        return tc if tc.available?
      end
      raise CompilerNotFoundError, "No supported C/C++ compiler found (tried clang, gcc, cl)"
    end

    def translate_flags(flags)
      unrecognized_flag = flags.find { |flag| !RECOGNIZED_FLAGS.include?(flag) }
      if unrecognized_flag
        raise "#{unrecognized_flag.inspect} is not a known flag"
      end

      flags.flat_map { |flag| @toolchain.flags[flag] }
    end

    def toolchain_classes
      TOOLCHAIN_CLASSES
    end

    def run_command(cmd, env: {}, working_dir: ".")
      out, err, status = Open3.capture3(env, *cmd, chdir: working_dir)
      record_output(cmd, out, err)
      status.success?
    end

    def record_output(command, stdout, stderr)
      entry = { command:, stdout:, stderr: }
      @log << entry
      @stdout_sink.write(stdout) if @stdout_sink.respond_to?(:write)
      @stderr_sink.write(stderr) if @stderr_sink.respond_to?(:write)
    end

    # Returns +path+ unchanged if it is absolute; otherwise joins it with
    # +output_dir+ so that output files land in the configured build directory.
    def resolve_output(path)
      File.absolute_path?(path) ? path : File.join(@output_dir, path)
    end

    # Returns true if +output_path+ exists and its mtime is newer than every
    # file in +input_paths+. Returns false if the output is missing, if any
    # input is missing, or if any input is as new as or newer than the output.
    def up_to_date?(output_path, input_paths)
      return false unless File.exist?(output_path)

      output_mtime = File.mtime(output_path)
      input_paths.all? { |p| File.exist?(p) && File.mtime(p) < output_mtime }
    end

  end

end
