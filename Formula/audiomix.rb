class Audiomix < Formula
  desc "Per-app volume, mute, and output device routing for macOS"
  homepage "https://github.com/mikevanl/audiomix"
  url "https://github.com/mikevanl/audiomix/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "594f8009686ce280fc780c8aba5f7ef92e3389a01432988a18a1ebdf536664a1"
  license "MIT"

  env :std

  depends_on :macos => :sonoma
  depends_on xcode: ["16.0", :build]
  depends_on "xcodegen" => :build

  def install
    system "xcodegen", "generate"

    ENV["SWIFT_PACKAGE_MANIFEST_SANDBOX"] = "none"

    system "xcodebuild", "-scheme", "AudioMix",
           "-destination", "platform=macOS",
           "-resolvePackageDependencies",
           "-skipPackagePluginValidation"

    xcodebuild_args = %w[
      -configuration Release
      -derivedDataPath build
      -skipPackagePluginValidation
      -disableAutomaticPackageResolution
      CODE_SIGN_IDENTITY=-
    ]

    system "xcodebuild", "-scheme", "AudioMix",
           "-destination", "platform=macOS",
           "build", *xcodebuild_args
    system "xcodebuild", "-scheme", "audiomix",
           "-destination", "platform=macOS",
           "build", *xcodebuild_args

    bin.install "build/Build/Products/Release/audiomix"

    app_dir = prefix/"AudioMix.app"
    app_dir.mkpath
    cp_r Dir["build/Build/Products/Release/AudioMix.app/*"], app_dir
  end

  def post_install
    system "codesign", "--force", "--deep", "--sign", "-", prefix/"AudioMix.app"
  end

  def caveats
    <<~EOS
      AudioMix.app has been installed to:
        #{prefix}/AudioMix.app

      To launch:
        open #{prefix}/AudioMix.app

      To install to /Applications (optional):
        cp -r #{prefix}/AudioMix.app /Applications/

      The CLI tool `audiomix` is available in your PATH.
      The app must be running for CLI commands to work.

      On first launch, grant Audio Capture permission when prompted.
    EOS
  end

  test do
    assert_match "audiomix", shell_output("#{bin}/audiomix --help")
  end
end
