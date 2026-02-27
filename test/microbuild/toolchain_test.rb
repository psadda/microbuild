require "test_helper"
require "securerandom"
require "tmpdir"
require "fileutils"

class MsvcToolchainTest < Minitest::Test

  # ---------------------------------------------------------------------------
  # Helper: minimal MsvcToolchain subclass that prevents real subprocess calls.
  #
  # Only command_available?, run_vswhere, and run_vcvarsall are overridden.
  # All other methods (setup_msvc_environment, find_vcvarsall, load_vcvarsall)
  # run their real implementations.
  # ---------------------------------------------------------------------------

  def stub_msvc_class(cl_on_path: false, &block)
    klass = Class.new(Microbuild::MsvcToolchain) do
      define_method(:command_available?) do |cmd|
        cl_on_path && (cmd == "cl" || cmd == "link" || cmd == "lib")
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
    klass = Class.new(Microbuild::MsvcToolchain) do
      define_method(:command_available?) { |cmd| cmd == "cl" }
    end
    tc = klass.new
    assert_equal "cl", tc.c
    assert_equal "cl", tc.cxx
    assert_equal "link", tc.ld
  end

  def test_available_returns_true_when_cl_is_on_path
    klass = Class.new(Microbuild::MsvcToolchain) do
      define_method(:command_available?) { |cmd| cmd == "cl" }
    end
    tc = klass.new
    assert tc.available?
  end

  # ---------------------------------------------------------------------------
  # Constructor postconditions: cl NOT on PATH, vswhere absent
  # ---------------------------------------------------------------------------

  def test_not_available_when_vswhere_absent
    tc = stub_msvc_class(cl_on_path: false).new
    refute tc.available?
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
  # load_vcvarsall: environment variable parsing
  # ---------------------------------------------------------------------------

  def test_load_vcvarsall_merges_env_variables
    key_a = "MICROBUILD_TEST_A_#{SecureRandom.hex(8)}"
    key_b = "MICROBUILD_TEST_B_#{SecureRandom.hex(8)}"
    output = "#{key_a}=test_value\n#{key_b}=another_value\n"

    tc = stub_msvc_class.new
    begin
      tc.send(:load_vcvarsall, output)
      assert_equal "test_value", ENV[key_a]
      assert_equal "another_value", ENV[key_b]
    ensure
      ENV.delete(key_a)
      ENV.delete(key_b)
    end
  end

  def test_load_vcvarsall_skips_lines_without_equals
    env_key = "MICROBUILD_TEST_#{SecureRandom.hex(8)}"
    output = "no_equals_sign\n#{env_key}=valid\n\n"

    tc = stub_msvc_class.new
    begin
      tc.send(:load_vcvarsall, output)
      assert_equal "valid", ENV[env_key]
    ensure
      ENV.delete(env_key)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration: full setup flow with vswhere and vcvarsall
  # ---------------------------------------------------------------------------

  def test_integration_setup_with_vswhere_and_vcvarsall
    env_key = "MICROBUILD_TEST_#{SecureRandom.hex(8)}"
    setup_done = false

    Dir.mktmpdir do |dir|
      vcvarsall_dir = File.join(dir, "VC", "Auxiliary", "Build")
      FileUtils.mkdir_p(vcvarsall_dir)
      vcvarsall_path = File.join(vcvarsall_dir, "vcvarsall.bat")
      File.write(vcvarsall_path, "")

      devenv = File.join(dir, "Common7", "IDE", "devenv.exe")

      klass = Class.new(Microbuild::MsvcToolchain) do
        define_method(:command_available?) do |cmd|
          setup_done && (cmd == "cl" || cmd == "link" || cmd == "lib")
        end
        define_method(:run_vswhere) { |*args| devenv }
        define_method(:run_vcvarsall) do |path|
          setup_done = true
          load_vcvarsall("#{env_key}=from_vcvarsall\n")
        end
      end

      begin
        tc = klass.new
        assert setup_done, "run_vcvarsall should have been called"
        assert tc.available?
        assert_equal "from_vcvarsall", ENV[env_key]
      ensure
        ENV.delete(env_key)
      end
    end
  end

end
