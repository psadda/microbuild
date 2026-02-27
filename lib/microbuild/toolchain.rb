module Microbuild

  # Base class for compiler toolchain command builders.
  # Subclasses implement the toolchain-specific flag and command logic.
  class Toolchain

    # @param compiler_info [CompilerInfo] the detected compiler information
    def initialize(compiler_info)
      @compiler_info = compiler_info
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

    attr_reader :compiler_info

    def c_file?(path)
      File.extname(path).downcase == ".c"
    end

  end

  # GNU-compatible toolchain (gcc).
  class GnuToolchain < Toolchain

    def compile_command(source, output, flags, include_paths, definitions)
      cc = c_file?(source) ? compiler_info.c : compiler_info.cxx
      inc_flags = include_paths.map { |p| "-I#{p}" }
      def_flags = definitions.map  { |d| "-D#{d}" }
      [cc, *flags, *inc_flags, *def_flags, "-c", source, "-o", output]
    end

    def link_executable_command(object_files, output)
      [compiler_info.ld, *object_files, "-o", output]
    end

    def link_shared_command(object_files, output)
      [compiler_info.ld, "-shared", *object_files, "-o", output]
    end

    def link_static_commands(object_files, output)
      cmds = [[compiler_info.ar, "rcs", output, *object_files]]
      cmds << [compiler_info.ranlib, output] if compiler_info.ranlib
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
      [compiler_info.c, *flags, *inc_flags, *def_flags, "/c", source, "/Fo#{output}"]
    end

    def link_executable_command(object_files, output)
      [compiler_info.ld, *object_files, "/OUT:#{output}"]
    end

    def link_shared_command(object_files, output)
      [compiler_info.ld, "/DLL", *object_files, "/OUT:#{output}"]
    end

    def link_static_commands(object_files, output)
      [[compiler_info.ar, "/OUT:#{output}", *object_files]]
    end

  end

end
