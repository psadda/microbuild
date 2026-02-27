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

    def initialize
      @type = :msvc
      @c    = "cl"
      @cxx  = "cl"
      @ld   = "link"
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

  end

end
