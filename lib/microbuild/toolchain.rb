require "open3"

module Microbuild

  # Base class for compiler toolchains.
  # Subclasses set their own command attributes in +initialize+ by calling
  # +command_available?+ to probe the system, then implement the
  # toolchain-specific flag and command building methods.
  #   type   – symbolic name (:clang, :gcc, :msvc)
  #   c      – command used to compile C source files
  #   cxx    – command used to compile C++ source files
  #   ld     – command used to link executables and shared libraries
  #   ar     – command used to create static libraries (nil if not found)
  #   ranlib – command used to index static libraries (nil if not found)
  class Toolchain

    attr_reader :type, :c, :cxx, :ld, :ar, :ranlib

    # Returns true if this toolchain's primary compiler is present in PATH.
    def available?
      command_available?(c)
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

    # Returns the full compile command for the given inputs.
    def compile_command(source, output, flags, include_paths, definitions)
      raise NotImplementedError, "#{self.class}#compile_command not implemented"
    end

    # Returns the full link-executable command for the given inputs.
    def link_executable_command(object_files, output)
      raise NotImplementedError, "#{self.class}#link_executable_command not implemented"
    end

    # Returns the full link-shared-library command for the given inputs.
    def link_shared_command(object_files, output)
      raise NotImplementedError, "#{self.class}#link_shared_command not implemented"
    end

    # Returns an array of commands to create a static archive.
    # Each element is a command array suitable for Open3.capture3.
    def link_static_commands(object_files, output)
      raise NotImplementedError, "#{self.class}#link_static_commands not implemented"
    end

    private

    def c_file?(path)
      File.extname(path).downcase == ".c"
    end

  end

  # GNU-compatible toolchain (gcc).
  class GnuToolchain < Toolchain

    def initialize
      @type   = :gcc
      @c      = "gcc"
      @cxx    = "g++"
      @ld     = "g++"
      @ar     = "ar"     if command_available?("ar")
      @ranlib = "ranlib" if command_available?("ranlib")
    end

    def compile_command(source, output, flags, include_paths, definitions)
      cc = c_file?(source) ? c : cxx
      inc_flags = include_paths.map { |p| "-I#{p}" }
      def_flags = definitions.map  { |d| "-D#{d}" }
      [cc, *flags, *inc_flags, *def_flags, "-c", source, "-o", output]
    end

    def link_executable_command(object_files, output)
      [ld, *object_files, "-o", output]
    end

    def link_shared_command(object_files, output)
      [ld, "-shared", *object_files, "-o", output]
    end

    def link_static_commands(object_files, output)
      cmds = [[ar, "rcs", output, *object_files]]
      cmds << [ranlib, output] if ranlib
      cmds
    end

  end

  # Clang toolchain – identical command structure to GNU.
  class ClangToolchain < GnuToolchain

    def initialize
      @type   = :clang
      @c      = "clang"
      @cxx    = "clang++"
      @ld     = "clang++"
      @ar     = "ar"     if command_available?("ar")
      @ranlib = "ranlib" if command_available?("ranlib")
    end

  end

  # Microsoft Visual C++ toolchain.
  class MsvcToolchain < Toolchain

    # Default location of the Visual Studio Installer's vswhere utility.
    VSWHERE_PATH = File.join(
      ENV.fetch("ProgramFiles(x86)", "C:\\Program Files (x86)"),
      "Microsoft Visual Studio", "Installer", "vswhere.exe"
    ).freeze

    def initialize
      @type = :msvc
      @c    = "cl"
      @cxx  = "cl"
      @ld   = "link"
      setup_msvc_environment
      @ar   = "lib" if command_available?("lib")
    end

    def compile_command(source, output, flags, include_paths, definitions)
      inc_flags = include_paths.map { |p| "/I#{p}" }
      def_flags = definitions.map  { |d| "/D#{d}" }
      [c, *flags, *inc_flags, *def_flags, "/c", source, "/Fo#{output}"]
    end

    def link_executable_command(object_files, output)
      [ld, *object_files, "/OUT:#{output}"]
    end

    def link_shared_command(object_files, output)
      [ld, "/DLL", *object_files, "/OUT:#{output}"]
    end

    def link_static_commands(object_files, output)
      [[ar, "/OUT:#{output}", *object_files]]
    end

    private

    # Attempts to configure the MSVC environment using vswhere.exe when cl.exe
    # is not already available on PATH.  Tries two vswhere strategies in order:
    #
    # 1. Query vswhere for VS instances whose tools are already on PATH (-path).
    # 2. Query vswhere for the latest VS instance, including prereleases.
    #
    # When a VS instance is found, locates vcvarsall.bat relative to the
    # returned devenv.exe path and runs it so that cl.exe and related tools
    # become available on PATH.
    def setup_msvc_environment
      return if command_available?("cl")

      devenv_path = find_msvc_via_vswhere
      return unless devenv_path

      vcvarsall = find_vcvarsall(devenv_path)
      return unless vcvarsall

      run_vcvarsall(vcvarsall)
    end

    # Queries vswhere.exe for a VS installation using a two-step strategy:
    # first for instances already on PATH, then for the latest available
    # instance (including prereleases).  Returns the path to devenv.exe,
    # or nil if vswhere is absent or reports no matching installation.
    def find_msvc_via_vswhere
      return nil unless vswhere_available?

      query_vswhere("-path", "-products", "*", "-property", "productPath") ||
        query_vswhere("-latest", "-products", "*", "-prerelease", "-property", "productPath")
    end

    # Returns true when vswhere.exe exists at its default installer location.
    def vswhere_available?
      File.exist?(VSWHERE_PATH)
    end

    # Runs vswhere.exe with the given arguments and returns the trimmed stdout,
    # or nil if the command fails or produces no output.
    def query_vswhere(*args)
      stdout, _, status = Open3.capture3(VSWHERE_PATH, *args)
      return nil unless status.success?
      path = stdout.strip
      path.empty? ? nil : path
    rescue Errno::ENOENT
      nil
    end

    # Returns the path to vcvarsall.bat for the given devenv.exe path, or nil
    # if it cannot be located.  devenv.exe lives at:
    #   <root>\Common7\IDE\devenv.exe
    # vcvarsall.bat lives at:
    #   <root>\VC\Auxiliary\Build\vcvarsall.bat
    def find_vcvarsall(devenv_path)
      install_root = File.expand_path("../../..", devenv_path)
      vcvarsall = File.join(install_root, "VC", "Auxiliary", "Build", "vcvarsall.bat")
      File.exist?(vcvarsall) ? vcvarsall : nil
    end

    # Runs vcvarsall.bat for the x64 architecture and merges the resulting
    # environment variables into the current process's ENV so that cl.exe
    # and related tools become available on PATH.
    def run_vcvarsall(vcvarsall)
      stdout, _, status = Open3.capture3("cmd.exe", "/c", "\"#{vcvarsall}\" x64 && set")
      return unless status.success?

      stdout.each_line do |line|
        key, sep, value = line.chomp.partition("=")
        next if sep.empty?
        ENV[key] = value
      end
    end

  end

end
