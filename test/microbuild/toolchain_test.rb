require "test_helper"
require "securerandom"

class MsvcToolchainTest < Minitest::Test

  # ---------------------------------------------------------------------------
  # Helper: build a controlled MsvcToolchain subclass.
  #
  # All subprocess calls are blocked by default so tests run on any platform.
  # Individual overrides can be supplied via the block.
  # ---------------------------------------------------------------------------

  # Returns a new MsvcToolchain subclass whose constructor-level probes are
  # fully controlled.  +cl_on_path+ governs whether cl.exe appears available
  # before any vswhere lookup.  The block, if given, is evaluated in the
  # context of the anonymous class so callers can add further overrides.
  def stub_msvc_class(cl_on_path: false, &block)
    klass = Class.new(Microbuild::MsvcToolchain) do
      # Prevent real subprocess calls for cl, link, lib, etc.
      define_method(:command_available?) do |cmd|
        cl_on_path && (cmd == "cl" || cmd == "link")
      end

      # Prevent real vswhere/vcvarsall calls unless overridden.
      def run_vswhere(*)   = nil
      def find_vcvarsall(*) = nil
      def run_vcvarsall(*) = nil
    end
    klass.class_eval(&block) if block
    klass
  end

  # ---------------------------------------------------------------------------
  # setup_msvc_environment: skip when cl is already on PATH
  # ---------------------------------------------------------------------------

  def test_setup_skips_vswhere_when_cl_already_available
    vswhere_called = false
    klass = stub_msvc_class(cl_on_path: true) do
      define_method(:run_vswhere) do |*args|
        vswhere_called = true
        nil
      end
    end
    klass.new
    refute vswhere_called, "vswhere should not be consulted when cl is already on PATH"
  end

  def test_available_returns_true_when_cl_is_on_path
    klass = stub_msvc_class(cl_on_path: true)
    tc = klass.new
    assert tc.available?, "available? should be true when cl is on PATH"
  end

  # ---------------------------------------------------------------------------
  # run_vswhere: returns nil when vswhere.exe is absent
  # ---------------------------------------------------------------------------

  def test_run_vswhere_returns_nil_when_vswhere_absent
    tc = Microbuild::MsvcToolchain.allocate

    File.stub(:exist?, false) do
      assert_nil tc.send(:run_vswhere, "-path", "-products", "*", "-property", "productPath")
    end
  end

  # ---------------------------------------------------------------------------
  # setup_msvc_environment: two-step vswhere query order
  # ---------------------------------------------------------------------------

  def test_setup_queries_path_flag_first
    queries = []
    klass = stub_msvc_class do
      define_method(:run_vswhere) do |*args|
        queries << args
        nil
      end
    end
    klass.new
    assert queries.size >= 1, "at least one vswhere query should be made"
    assert_equal ["-path", "-products", "*", "-property", "productPath"], queries.first,
                 "first query must use the -path flag"
  end

  def test_setup_falls_back_to_latest_when_path_returns_nil
    queries = []
    klass = stub_msvc_class do
      define_method(:run_vswhere) do |*args|
        queries << args
        nil  # both queries return nil
      end
    end
    klass.new
    assert_equal 2, queries.size, "both vswhere queries should be attempted"
    second = queries[1]
    assert_includes second, "-latest",     "second query must include -latest"
    assert_includes second, "-prerelease", "second query must include -prerelease"
  end

  def test_setup_stops_after_path_query_succeeds
    queries = []
    klass = stub_msvc_class do
      define_method(:run_vswhere) do |*args|
        queries << args
        # Only the -path query succeeds.
        args.include?("-path") ? "/fake/VS/Common7/IDE/devenv.exe" : nil
      end
    end
    klass.new
    assert_equal 1, queries.size, "should stop after the -path query succeeds"
    assert_equal ["-path", "-products", "*", "-property", "productPath"], queries.first
  end

  def test_setup_uses_latest_result_when_path_query_fails
    latest_devenv = "/fake/VS/Common7/IDE/devenv.exe"
    vcvarsall_arg = nil
    klass = stub_msvc_class do
      define_method(:run_vswhere) do |*args|
        args.include?("-latest") ? latest_devenv : nil
      end
      define_method(:find_vcvarsall) { |path| vcvarsall_arg = path; nil }
    end
    klass.new
    assert_equal latest_devenv, vcvarsall_arg,
                 "find_vcvarsall should be called with the latest devenv path"
  end

  # ---------------------------------------------------------------------------
  # find_vcvarsall: path derivation from devenv.exe
  # ---------------------------------------------------------------------------

  def test_find_vcvarsall_derives_correct_path
    tc = Microbuild::MsvcToolchain.allocate

    # Use POSIX-style paths so the test runs on Linux too.
    devenv   = "/fake/VS/Common7/IDE/devenv.exe"
    expected = "/fake/VS/VC/Auxiliary/Build/vcvarsall.bat"

    File.stub(:exist?, true) do
      result = tc.send(:find_vcvarsall, devenv)
      assert_equal expected, result
    end
  end

  def test_find_vcvarsall_returns_nil_when_bat_absent
    tc = Microbuild::MsvcToolchain.allocate

    File.stub(:exist?, false) do
      assert_nil tc.send(:find_vcvarsall, "/fake/VS/Common7/IDE/devenv.exe")
    end
  end

  # ---------------------------------------------------------------------------
  # run_vcvarsall: environment variable parsing
  # ---------------------------------------------------------------------------

  def test_run_vcvarsall_merges_env_variables
    tc = Microbuild::MsvcToolchain.allocate

    # Choose a key unlikely to collide with real env vars.
    env_key = "MICROBUILD_TEST_#{SecureRandom.hex(8)}"
    fake_output = "#{env_key}=test_value\nANOTHER_KEY=another_value\n"
    fake_status = Struct.new(:success?).new(true)

    begin
      Open3.stub(:capture3, [fake_output, "", fake_status]) do
        tc.send(:run_vcvarsall, "/fake/vcvarsall.bat")
      end
      assert_equal "test_value", ENV[env_key]
    ensure
      ENV.delete(env_key)
      ENV.delete("ANOTHER_KEY")
    end
  end

  def test_run_vcvarsall_does_nothing_when_cmd_fails
    tc = Microbuild::MsvcToolchain.allocate

    env_key = "MICROBUILD_TEST_#{SecureRandom.hex(8)}"
    fake_output = "#{env_key}=should_not_be_set\n"
    fake_status = Struct.new(:success?).new(false)  # failure

    begin
      Open3.stub(:capture3, [fake_output, "", fake_status]) do
        tc.send(:run_vcvarsall, "/fake/vcvarsall.bat")
      end
      assert_nil ENV[env_key], "ENV should not be modified when vcvarsall.bat fails"
    ensure
      ENV.delete(env_key)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration: available? after successful environment setup
  # ---------------------------------------------------------------------------

  def test_available_after_successful_vswhere_and_vcvarsall_setup
    # Simulate: cl not on PATH, vswhere finds a devenv, vcvarsall sets up cl.
    # Use define_method closures so test state stays scoped to this method.
    setup_done = false

    klass = stub_msvc_class do
      define_method(:run_vswhere) do |*args|
        args.include?("-path") ? "/fake/VS/Common7/IDE/devenv.exe" : nil
      end
      define_method(:find_vcvarsall) { |_| "/fake/VS/VC/Auxiliary/Build/vcvarsall.bat" }
      define_method(:run_vcvarsall)  { |_| setup_done = true }
      # After setup, report cl as available (simulating the env change).
      define_method(:command_available?) { |cmd| setup_done && cmd == "cl" }
    end

    tc = klass.new
    assert setup_done, "run_vcvarsall should have been called during initialization"
    assert tc.available?, "available? should be true after environment setup"
  end

end

