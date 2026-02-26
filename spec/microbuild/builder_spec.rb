require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Microbuild::Builder do
  # ---------------------------------------------------------------------------
  # Constructor / compiler detection
  # ---------------------------------------------------------------------------
  describe "#initialize" do
    context "when at least one compiler is available" do
      it "creates a Builder instance without raising" do
        # The CI environment has clang or gcc installed.
        expect { described_class.new }.not_to raise_error
      end

      it "populates #compiler with a known type" do
        builder = described_class.new
        expect([:clang, :gcc, :msvc]).to include(builder.compiler[:type])
      end
    end

    context "when no compiler is available" do
      it "raises CompilerNotFoundError" do
        allow_any_instance_of(described_class).to receive(:compiler_available?).and_return(false)
        expect { described_class.new }.to raise_error(Microbuild::CompilerNotFoundError)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #compile
  # ---------------------------------------------------------------------------
  describe "#compile" do
    let(:builder) { described_class.new }

    context "with a valid C source file" do
      it "returns true and produces an object file" do
        Dir.mktmpdir do |dir|
          src = File.join(dir, "hello.c")
          obj = File.join(dir, "hello.o")
          File.write(src, "int main(void) { return 0; }\n")

          result = builder.compile(src, obj, flags: [], include_paths: [], definitions: [])
          expect(result).to be true
          expect(File.exist?(obj)).to be true
        end
      end
    end

    context "with a valid C++ source file" do
      it "returns true and produces an object file" do
        Dir.mktmpdir do |dir|
          src = File.join(dir, "hello.cpp")
          obj = File.join(dir, "hello.o")
          File.write(src, "int main() { return 0; }\n")

          result = builder.compile(src, obj, flags: [], include_paths: [], definitions: [])
          expect(result).to be true
          expect(File.exist?(obj)).to be true
        end
      end
    end

    context "with include_paths and definitions" do
      it "passes them to the compiler and succeeds" do
        Dir.mktmpdir do |dir|
          # Create a header in a subdirectory
          inc_dir = File.join(dir, "include")
          FileUtils.mkdir_p(inc_dir)
          File.write(File.join(inc_dir, "config.h"), "#define ANSWER 42\n")

          src = File.join(dir, "main.c")
          obj = File.join(dir, "main.o")
          File.write(src, "#include <config.h>\nint main(void) { return ANSWER - ANSWER; }\n")

          result = builder.compile(
            src, obj,
            flags: [],
            include_paths: [inc_dir],
            definitions: ["UNUSED=1"]
          )
          expect(result).to be true
          expect(File.exist?(obj)).to be true
        end
      end
    end

    context "with a source file that has a syntax error" do
      it "returns false" do
        Dir.mktmpdir do |dir|
          src = File.join(dir, "broken.c")
          obj = File.join(dir, "broken.o")
          File.write(src, "this is not valid C code {\n")

          result = builder.compile(src, obj, flags: [], include_paths: [], definitions: [])
          expect(result).to be false
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #link
  # ---------------------------------------------------------------------------
  describe "#link" do
    let(:builder) { described_class.new }

    context "with valid object files" do
      it "returns true and produces an executable" do
        Dir.mktmpdir do |dir|
          src = File.join(dir, "main.c")
          obj = File.join(dir, "main.o")
          exe = File.join(dir, "main")
          File.write(src, "int main(void) { return 0; }\n")

          builder.compile(src, obj, flags: [], include_paths: [], definitions: [])
          result = builder.link([obj], exe)
          expect(result).to be true
          expect(File.exist?(exe)).to be true
        end
      end
    end

    context "when linking fails (missing object file)" do
      it "returns false" do
        Dir.mktmpdir do |dir|
          exe = File.join(dir, "output")
          result = builder.link([File.join(dir, "nonexistent.o")], exe)
          expect(result).to be false
        end
      end
    end
  end
end
