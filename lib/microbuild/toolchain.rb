module Microbuild

  # Base class for compiler toolchains.
  # Carries the detected compiler command names and implements
  # toolchain-specific flag and command building in subclasses.
  #   type   – symbolic name (:clang, :gcc, :msvc)
  #   c      – command used to compile C source files
  #   cxx    – command used to compile C++ source files
  #   ld     – command used to link executables and shared libraries
  #   ar     – command used to create static libraries (nil if not found)
  #   ranlib – command used to index static libraries (nil if not found)
  class Toolchain

    attr_reader :type, :c, :cxx, :ld, :ar, :ranlib

    def initialize(type, c, cxx, ld, ar, ranlib)
      @type   = type
      @c      = c
      @cxx    = cxx
      @ld     = ld
      @ar     = ar
      @ranlib = ranlib
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
  class ClangToolchain < GnuToolchain; end

  # Microsoft Visual C++ toolchain.
  class MsvcToolchain < Toolchain

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
