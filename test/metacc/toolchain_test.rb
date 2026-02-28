# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "tmpdir"
require "fileutils"
require "metacc/toolchain"


class MsvcToolchainTest < Minitest::Test

  # ---------------------------------------------------------------------------
  # Helper: minimal MsvcToolchain subclass that prevents real subprocess calls.
  #
  # Only command_available?, run_vswhere, and run_vcvarsall are overridden.
  # All other methods (setup_msvc_environment, find_vcvarsall, load_vcvarsall)
  # run their real implementations.
  # ---------------------------------------------------------------------------

  def stub_msvc_class(cl_on_path: false, &block)
    klass = Class.new(MetaCC::MsvcToolchain) do
      define_method(:command_available?) do |cmd|
        cl_on_path && cmd == "cl"
      end

      def run_vswhere(*)   = nil
      def run_vcvarsall(*) = nil
    end
    klass.class_eval(&block) if block
    klass
  end

  # ---------------------------------------------------------------------------
  # Constructor postconditions: cl already on PATH
  # ---------------------------------------------------------------------------

  def test_setup_when_cl_already_available
    klass = Class.new(MetaCC::MsvcToolchain) do
      define_method(:command_available?) { |cmd| cmd == "cl" }
    end
    tc = klass.new

    assert_equal "cl", tc.c
    assert_equal "cl", tc.cxx
  end

  def test_available_returns_true_when_cl_is_on_path
    klass = Class.new(MetaCC::MsvcToolchain) do
      define_method(:command_available?) { |cmd| cmd == "cl" }
    end
    tc = klass.new

    assert_predicate tc, :available?
  end

  # ---------------------------------------------------------------------------
  # Constructor postconditions: cl NOT on PATH, vswhere absent
  # ---------------------------------------------------------------------------

  def test_not_available_when_vswhere_absent
    tc = stub_msvc_class(cl_on_path: false).new

    refute_predicate tc, :available?
  end

  # ---------------------------------------------------------------------------
  # find_vcvarsall: path derivation from devenv.exe
  # ---------------------------------------------------------------------------

  def test_find_vcvarsall_derives_correct_path
    Dir.mktmpdir do |dir|
      vcvarsall_dir = File.join(dir, "VC", "Auxiliary", "Build")
      FileUtils.mkdir_p(vcvarsall_dir)
      vcvarsall_path = File.join(vcvarsall_dir, "vcvarsall.bat")
      File.write(vcvarsall_path, "")

      devenv = File.join(dir, "Common7", "IDE", "devenv.exe")

      tc = stub_msvc_class.new

      assert_equal vcvarsall_path, tc.send(:find_vcvarsall, devenv)
    end
  end

  def test_find_vcvarsall_returns_nil_when_bat_absent
    tc = stub_msvc_class.new

    assert_nil tc.send(:find_vcvarsall, "/nonexistent/Common7/IDE/devenv.exe")
  end

  # ---------------------------------------------------------------------------
  # vcvarsall_command: cmd.exe command string construction
  # ---------------------------------------------------------------------------

  # Helper: minimal MsvcToolchain instance with only the pure vcvarsall_command
  # method available.  Defines its own initialize to avoid the pre-existing
  # super arity issue in MsvcToolchain#initialize.
  def msvc_for_vcvarsall_command
    Class.new(MetaCC::MsvcToolchain) do
      def command_available?(_cmd) = false
      def run_vswhere(*)   = nil
      def run_vcvarsall(*) = nil
    end.new
  end

  def test_vcvarsall_command_plain_path
    tc = msvc_for_vcvarsall_command
    cmd = tc.send(:vcvarsall_command, 'C:\\VS\\VC\\Auxiliary\\Build\\vcvarsall.bat')

    assert_equal '"C:\\VS\\VC\\Auxiliary\\Build\\vcvarsall.bat" x64 && set', cmd
  end

  def test_vcvarsall_command_path_with_spaces
    tc = msvc_for_vcvarsall_command
    cmd = tc.send(:vcvarsall_command, 'C:\\Program Files\\VS\\VC\\Auxiliary\\Build\\vcvarsall.bat')

    assert_equal '"C:\\Program Files\\VS\\VC\\Auxiliary\\Build\\vcvarsall.bat" x64 && set', cmd
  end

  def test_vcvarsall_command_path_with_embedded_double_quotes
    tc = msvc_for_vcvarsall_command
    cmd = tc.send(:vcvarsall_command, 'C:\\path"with"quotes\\vcvarsall.bat')

    assert_equal '"C:\\path""with""quotes\\vcvarsall.bat" x64 && set', cmd
  end

  # ---------------------------------------------------------------------------
  # load_vcvarsall: environment variable parsing
  # ---------------------------------------------------------------------------

  def test_load_vcvarsall_merges_env_variables
    key_a = "METACC_TEST_A_#{SecureRandom.hex(8)}"
    key_b = "METACC_TEST_B_#{SecureRandom.hex(8)}"
    output = "#{key_a}=test_value\n#{key_b}=another_value\n"

    tc = stub_msvc_class.new
    begin
      tc.send(:load_vcvarsall, output)

      assert_equal "test_value", ENV.fetch(key_a, nil)
      assert_equal "another_value", ENV.fetch(key_b, nil)
    ensure
      ENV.delete(key_a)
      ENV.delete(key_b)
    end
  end

  def test_load_vcvarsall_skips_lines_without_equals
    env_key = "METACC_TEST_#{SecureRandom.hex(8)}"
    output = "no_equals_sign\n#{env_key}=valid\n\n"

    tc = stub_msvc_class.new
    begin
      tc.send(:load_vcvarsall, output)

      assert_equal "valid", ENV.fetch(env_key, nil)
    ensure
      ENV.delete(env_key)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration: full setup flow with vswhere and vcvarsall
  # ---------------------------------------------------------------------------

  def test_integration_setup_with_vswhere_and_vcvarsall
    env_key = "METACC_TEST_#{SecureRandom.hex(8)}"
    setup_done = false

    Dir.mktmpdir do |dir|
      vcvarsall_dir = File.join(dir, "VC", "Auxiliary", "Build")
      FileUtils.mkdir_p(vcvarsall_dir)
      vcvarsall_path = File.join(vcvarsall_dir, "vcvarsall.bat")
      File.write(vcvarsall_path, "")

      devenv = File.join(dir, "Common7", "IDE", "devenv.exe")

      klass = Class.new(MetaCC::MsvcToolchain) do
        define_method(:command_available?) do |cmd|
          setup_done && cmd == "cl"
        end
        define_method(:run_vswhere) { |*_args| devenv }
        define_method(:run_vcvarsall) do |_path|
          setup_done = true
          load_vcvarsall("#{env_key}=from_vcvarsall\n")
        end
      end

      begin
        tc = klass.new

        assert setup_done, "run_vcvarsall should have been called"
        assert_predicate tc, :available?
        assert_equal "from_vcvarsall", ENV.fetch(env_key, nil)
      ensure
        ENV.delete(env_key)
      end
    end
  end

end

class ClangClToolchainTest < Minitest::Test

  # ---------------------------------------------------------------------------
  # Helper: minimal ClangClToolchain subclass that prevents real subprocess calls.
  # ---------------------------------------------------------------------------

  def stub_clang_cl_class(clang_cl_on_path: false, &block)
    klass = Class.new(MetaCC::ClangClToolchain) do
      define_method(:command_available?) do |cmd|
        clang_cl_on_path && cmd == "clang-cl"
      end

      def run_vswhere(*)   = nil
      def run_vcvarsall(*) = nil
    end
    klass.class_eval(&block) if block
    klass
  end

  # ---------------------------------------------------------------------------
  # Constructor postconditions
  # ---------------------------------------------------------------------------

  def test_compiler_commands_are_clang_cl
    tc = stub_clang_cl_class(clang_cl_on_path: true).new

    assert_equal "clang-cl", tc.c
    assert_equal "clang-cl", tc.cxx
  end

  def test_available_returns_true_when_clang_cl_is_on_path
    tc = stub_clang_cl_class(clang_cl_on_path: true).new

    assert_predicate tc, :available?
  end

  def test_not_available_when_clang_cl_absent
    tc = stub_clang_cl_class(clang_cl_on_path: false).new

    refute_predicate tc, :available?
  end

  # ---------------------------------------------------------------------------
  # Flags: inherits MSVC-compatible flags
  # ---------------------------------------------------------------------------

  def test_flags_returns_clang_cl_flags
    tc = stub_clang_cl_class(clang_cl_on_path: true).new

    assert_equal MetaCC::ClangClToolchain::CLANG_CL_FLAGS, tc.flags
  end

  # ---------------------------------------------------------------------------
  # Integration: full setup flow with vswhere and vcvarsall
  # ---------------------------------------------------------------------------

  def test_integration_setup_with_vswhere_and_vcvarsall
    env_key = "METACC_TEST_#{SecureRandom.hex(8)}"
    setup_done = false

    Dir.mktmpdir do |dir|
      vcvarsall_dir = File.join(dir, "VC", "Auxiliary", "Build")
      FileUtils.mkdir_p(vcvarsall_dir)
      vcvarsall_path = File.join(vcvarsall_dir, "vcvarsall.bat")
      File.write(vcvarsall_path, "")

      devenv = File.join(dir, "Common7", "IDE", "devenv.exe")

      klass = Class.new(MetaCC::ClangClToolchain) do
        define_method(:command_available?) do |cmd|
          setup_done && cmd == "clang-cl"
        end
        define_method(:run_vswhere) { |*_args| devenv }
        define_method(:run_vcvarsall) do |_path|
          setup_done = true
          load_vcvarsall("#{env_key}=from_vcvarsall\n")
        end
      end

      begin
        tc = klass.new

        assert_predicate tc, :available?
        assert_equal "from_vcvarsall", ENV.fetch(env_key, nil)
      ensure
        ENV.delete(env_key)
      end
    end
  end

end

class GnuToolchainCommandTest < Minitest::Test

  # GnuToolchain#command is a pure method – no subprocess calls needed.

  def gnu
    Class.new(MetaCC::GnuToolchain) do
      def command_available?(_cmd) = true
    end.new
  end

  # ---------------------------------------------------------------------------
  # libs: linker flags
  # ---------------------------------------------------------------------------

  def test_libs_produce_dash_l_flags_in_link_mode
    cmd = gnu.command(["main.o"], "main", [], [], [], %w[m pthread], [])

    assert_includes cmd, "-lm"
    assert_includes cmd, "-lpthread"
  end

  def test_libs_omitted_in_compile_only_mode
    cmd = gnu.command(["main.c"], "main.o", ["-c"], [], [], ["m"], [])

    refute_includes cmd, "-lm"
  end

  # ---------------------------------------------------------------------------
  # linker_include_dirs: search path flags
  # ---------------------------------------------------------------------------

  def test_linker_include_dirs_produce_dash_L_flags_in_link_mode
    cmd = gnu.command(["main.o"], "main", [], [], [], [], ["/opt/lib", "/usr/local/lib"])

    assert_includes cmd, "-L/opt/lib"
    assert_includes cmd, "-L/usr/local/lib"
  end

  def test_linker_include_dirs_omitted_in_compile_only_mode
    cmd = gnu.command(["main.c"], "main.o", ["-c"], [], [], [], ["/opt/lib"])

    refute_includes cmd, "-L/opt/lib"
  end

  # ---------------------------------------------------------------------------
  # strip flag
  # ---------------------------------------------------------------------------

  def test_strip_flag_maps_to_wl_strip_unneeded
    assert_equal ["-Wl,--strip-unneeded"], MetaCC::GnuToolchain::GNU_FLAGS[:strip]
  end

end

class MsvcToolchainCommandTest < Minitest::Test

  # Override initialize to avoid the super arity issue in MsvcToolchain#initialize,
  # following the same pattern as msvc_for_vcvarsall_command in MsvcToolchainTest.
  def msvc
    Class.new(MetaCC::MsvcToolchain) do
      def command_available?(_cmd) = false
      def run_vswhere(*)   = nil
      def run_vcvarsall(*) = nil
    end.new
  end

  # ---------------------------------------------------------------------------
  # libs: library arguments
  # ---------------------------------------------------------------------------

  def test_libs_produce_dot_lib_in_link_mode
    cmd = msvc.command(["main.obj"], "main.exe", [], [], [], %w[user32 gdi32], [])

    assert_includes cmd, "user32.lib"
    assert_includes cmd, "gdi32.lib"
  end

  def test_libs_omitted_in_compile_only_mode
    cmd = msvc.command(["main.c"], "main.obj", ["/c"], [], [], ["user32"], [])

    refute_includes cmd, "user32.lib"
  end

  # ---------------------------------------------------------------------------
  # linker_include_dirs: /link /LIBPATH:
  # ---------------------------------------------------------------------------

  def test_linker_include_dirs_produce_libpath_in_link_mode
    cmd = msvc.command(["main.obj"], "main.exe", [], [], [], [], ["C:\\mylibs"])

    assert_includes cmd, "/link"
    assert_includes cmd, "/LIBPATH:C:\\mylibs"
  end

  def test_linker_include_dirs_omitted_in_compile_only_mode
    cmd = msvc.command(["main.c"], "main.obj", ["/c"], [], [], [], ["C:\\mylibs"])

    refute_includes cmd, "/link"
    refute_includes cmd, "/LIBPATH:C:\\mylibs"
  end

  def test_link_switch_absent_when_no_linker_include_dirs
    cmd = msvc.command(["main.obj"], "main.exe", [], [], [], [], [])

    refute_includes cmd, "/link"
  end

  # ---------------------------------------------------------------------------
  # strip flag
  # ---------------------------------------------------------------------------

  def test_strip_flag_maps_to_empty_array
    assert_equal [], MetaCC::MsvcToolchain::MSVC_FLAGS[:strip]
  end

end
