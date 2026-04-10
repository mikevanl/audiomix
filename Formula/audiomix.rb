class Audiomix < Formula
  desc "Per-app volume, mute, and output device routing for macOS"
  homepage "https://github.com/yourusername/audiomix"
  url "https://github.com/yourusername/audiomix.git", tag: "v0.1.0"
  license "MIT"

  depends_on :macos => :sonoma
  depends_on :xcode => ["16.0", :build]
  depends_on "xcodegen" => :build

  def install
    system "xcodegen", "generate"

    xcodebuild_args = %w[
      -configuration Release
      -destination platform=macOS
      -derivedDataPath build
      SYMROOT=build
    ]

    system "xcodebuild", "-scheme", "AudioMix", "build", *xcodebuild_args
    system "xcodebuild", "-scheme", "audiomix", "build", *xcodebuild_args

    prefix.install Dir["build/Release/AudioMix.app"]
    bin.install "build/Release/audiomix"
  end

  def caveats
    <<~EOS
      AudioMix.app has been installed to:
        #{prefix}/AudioMix.app

      To launch the app:
        open #{prefix}/AudioMix.app

      The CLI tool `audiomix` is available in your PATH.
      The app must be running for CLI commands to work.

      On first launch, grant Audio Capture permission when prompted.
    EOS
  end

  test do
    assert_match "audiomix", shell_output("#{bin}/audiomix --help")
  end
end
