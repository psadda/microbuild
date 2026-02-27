module Microbuild

  # Holds toolchain-specific flag arrays for common compilation options.
  # Each attribute is an Array of String flags to pass to the compiler.
  # An empty array means the option has no equivalent for this toolchain.
  #
  # Attributes:
  #   o0            – disable optimisation
  #   o1            – minimal optimisation
  #   o2            – moderate optimisation
  #   o3            – aggressive optimisation
  #   sse4_2        – enable x86-64-v2 microarchitecture level
  #   avx           – enable x86-64-v2 microarchitecture level plus AVX instructions
  #   avx2          – enable x86-64-v3 microarchitecture level
  #   avx512        – enable x86-64-v4 microarchitecture level
  #   native        – optimize for the capabilities of the host CPU
  #   debug         – emit debug symbols
  #   lto           – enable link-time optimisation
  #   warn_all      – enable a broad set of warnings
  #   warn_error    – treat all warnings as errors
  #   c11           – compile as C11
  #   c17           – compile as C17
  #   c23           – compile as C23
  #   cxx11         – compile as C++11
  #   cxx14         – compile as C++14
  #   cxx17         – compile as C++17
  #   cxx20         – compile as C++20
  #   cxx23         – compile as C++23
  #   cxx26         – compile as C++26
  #   asan          – enable AddressSanitizer
  #   ubsan         – enable UndefinedBehaviorSanitizer
  #   msan          – enable MemorySanitizer
  #   no_rtti       – disable C++ run-time type information
  #   no_exceptions – disable C++ exceptions
  #   pic           – generate position-independent code
  class UniversalFlags

    ATTRIBUTES = %i[
      o0 o1 o2 o3
      sse4_2 avx avx2 avx512 native
      debug lto
      warn_all warn_error
      c11 c17 c23
      cxx11 cxx14 cxx17 cxx20 cxx23 cxx26
      asan ubsan msan
      no_rtti no_exceptions pic
    ].freeze

    ATTRIBUTES.each { |name| attr_reader name }

    def initialize(**kwargs)
      ATTRIBUTES.each do |name|
        instance_variable_set(:"@#{name}", kwargs.fetch(name, []))
      end
    end

  end

end
