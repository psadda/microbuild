require "test_helper"
require "securerandom"
require "tmpdir"
require "fileutils"
require "microbuild/toolchain"

# ---------------------------------------------------------------------------
# UniversalFlags tests
# ---------------------------------------------------------------------------

class UniversalFlagsTest < Minitest::Test

  def test_all_attributes_default_to_empty_array
    f = Microbuild::UniversalFlags.new
    Microbuild::UniversalFlags::ATTRIBUTES.each do |attr|
      assert_equal [], f.public_send(attr), "Expected #{attr} to default to []"
    end
  end

  def test_provided_values_are_stored
    f = Microbuild::UniversalFlags.new(o0: ["-O0"], warn_all: ["-Wall", "-Wextra"])
    assert_equal ["-O0"], f.o0
    assert_equal ["-Wall", "-Wextra"], f.warn_all
  end

  def test_unspecified_attributes_remain_empty
    f = Microbuild::UniversalFlags.new(o2: ["-O2"])
    assert_equal [], f.o3
    assert_equal [], f.debug
  end

end

# ---------------------------------------------------------------------------
# GnuToolchain#flags tests
# ---------------------------------------------------------------------------

class GnuToolchainFlagsTest < Minitest::Test

  def setup
    klass = Class.new(Microbuild::GnuToolchain) do
      def command_available?(*) = false
    end
    @tc = klass.new
    @f  = @tc.flags
  end

  def test_flags_returns_universal_flags_instance
    assert_instance_of Microbuild::UniversalFlags, @f
  end

  def test_o0
    assert_equal ["-O0"], @f.o0
  end

  def test_o2
    assert_equal ["-O2"], @f.o2
  end

  def test_o3
    assert_equal ["-O3"], @f.o3
  end

  def test_avx
    assert_equal ["-mavx"], @f.avx
  end

  def test_avx2
    assert_equal ["-mavx2"], @f.avx2
  end

  def test_avx512
    assert_equal ["-mavx512f"], @f.avx512
  end

  def test_sse4_1
    assert_equal ["-msse4.1"], @f.sse4_1
  end

  def test_sse4_2
    assert_equal ["-msse4.2"], @f.sse4_2
  end

  def test_debug
    assert_equal ["-g"], @f.debug
  end

  def test_lto_thin
    assert_equal ["-flto"], @f.lto_thin
  end

  def test_warn_all
    assert_equal ["-Wall", "-Wextra", "-pedantic"], @f.warn_all
  end

  def test_warn_error
    assert_equal ["-Werror"], @f.warn_error
  end

  def test_c_standards
    assert_equal ["-std=c11"],  @f.c11
    assert_equal ["-std=c17"],  @f.c17
    assert_equal ["-std=c23"],  @f.c23
  end

  def test_cxx_standards
    assert_equal ["-std=c++11"], @f.cxx11
    assert_equal ["-std=c++14"], @f.cxx14
    assert_equal ["-std=c++17"], @f.cxx17
    assert_equal ["-std=c++20"], @f.cxx20
    assert_equal ["-std=c++23"], @f.cxx23
  end

  def test_sanitizers
    assert_equal ["-fsanitize=address"],   @f.asan
    assert_equal ["-fsanitize=undefined"], @f.ubsan
    assert_equal ["-fsanitize=memory"],    @f.msan
  end

  def test_extra_flags
    assert_equal ["-ffast-math"],    @f.fast_math
    assert_equal ["-fno-rtti"],      @f.rtti_off
    assert_equal ["-fno-exceptions"],@f.exceptions_off
    assert_equal ["-fPIC"],          @f.pic
  end

end

# ---------------------------------------------------------------------------
# ClangToolchain#flags tests – only the differences from GNU
# ---------------------------------------------------------------------------

class ClangToolchainFlagsTest < Minitest::Test

  def setup
    klass = Class.new(Microbuild::ClangToolchain) do
      def command_available?(*) = false
    end
    @f = klass.new.flags
  end

  def test_flags_returns_universal_flags_instance
    assert_instance_of Microbuild::UniversalFlags, @f
  end

  def test_lto_thin_uses_flto_equals_thin
    assert_equal ["-flto=thin"], @f.lto_thin
  end

  def test_other_flags_match_gnu
    assert_equal ["-O3"],             @f.o3
    assert_equal ["-mavx"],           @f.avx
    assert_equal ["-Wall", "-Wextra", "-pedantic"], @f.warn_all
    assert_equal ["-std=c++17"],      @f.cxx17
    assert_equal ["-fsanitize=address"], @f.asan
  end

end

# ---------------------------------------------------------------------------
# MsvcToolchain#flags tests
# ---------------------------------------------------------------------------

class MsvcToolchainFlagsTest < Minitest::Test

  def setup
    klass = Class.new(Microbuild::MsvcToolchain) do
      def command_available?(*) = false
      def run_vswhere(*)   = nil
      def run_vcvarsall(*) = nil
    end
    @f = klass.new.flags
  end

  def test_flags_returns_universal_flags_instance
    assert_instance_of Microbuild::UniversalFlags, @f
  end

  def test_o0
    assert_equal ["/Od"], @f.o0
  end

  def test_o2
    assert_equal ["/O2"], @f.o2
  end

  def test_o3
    assert_equal ["/O2", "/Ob3"], @f.o3
  end

  def test_avx
    assert_equal ["/arch:AVX"], @f.avx
  end

  def test_avx2
    assert_equal ["/arch:AVX2"], @f.avx2
  end

  def test_avx512
    assert_equal ["/arch:AVX512"], @f.avx512
  end

  def test_sse4_1
    assert_equal ["/arch:AVX"], @f.sse4_1
  end

  def test_sse4_2
    assert_equal ["/arch:AVX"], @f.sse4_2
  end

  def test_debug
    assert_equal ["/Zi"], @f.debug
  end

  def test_lto_thin
    assert_equal ["/GL"], @f.lto_thin
  end

  def test_warn_all
    assert_equal ["/W4"], @f.warn_all
  end

  def test_warn_error
    assert_equal ["/WX"], @f.warn_error
  end

  def test_c_standards
    assert_equal ["/std:c11"],     @f.c11
    assert_equal ["/std:c17"],     @f.c17
    assert_equal ["/std:clatest"], @f.c23
  end

  def test_cxx_standards
    assert_equal [],                @f.cxx11
    assert_equal ["/std:c++14"],    @f.cxx14
    assert_equal ["/std:c++17"],    @f.cxx17
    assert_equal ["/std:c++20"],    @f.cxx20
    assert_equal ["/std:c++latest"],@f.cxx23
  end

  def test_asan
    assert_equal ["/fsanitize=address"], @f.asan
  end

  def test_ubsan_and_msan_have_no_equivalent
    assert_equal [], @f.ubsan
    assert_equal [], @f.msan
  end

  def test_extra_flags
    assert_equal ["/fp:fast"],        @f.fast_math
    assert_equal ["/GR-"],            @f.rtti_off
    assert_equal ["/EHs-", "/EHc-"], @f.exceptions_off
    assert_equal [],                  @f.pic
  end

end



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
