{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.gha-runner.irl.runners;

  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;

  buildToolsVersion = "37.0.0";

  emptySysImgXml = pkgs.writeText "sys-img2-3.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <sys-img:sdk-sys-img xmlns:sys-img="http://schemas.android.com/sdk/android/repo/sys-img2/03"/>
  '';
  emptyAddonXml = pkgs.writeText "addon2-3.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <addon:sdk-addon xmlns:addon="http://schemas.android.com/sdk/android/repo/addon2/03"/>
  '';

  androidComposition = pkgs.androidenv.composeAndroidPackages {
    repoXmls = {
      packages = [ ./android-repo/repository2-3.xml ];
      images = [ emptySysImgXml ];
      addons = [ emptyAddonXml ];
    };
    buildToolsVersions = [ buildToolsVersion ];
    platformVersions = [
      "37.0"
      "37.2"
    ];
    platformToolsVersion = "37.0.1";
    cmakeVersions = [ "3.22.1" ];
    includeNDK = true;
    ndkVersions = [ "28.2.13676358" ];
  };
  androidHome = "${androidComposition.androidsdk}/libexec/android-sdk";

  labels = if isDarwin then [ "macOS" ] else [ "linux" ];

  extraPackages =
    (with pkgs; [
      git-lfs
      zulu21
      zulu25
      firebase-tools
      python3
      gawk
      jq
      curl
      ninja
      gn
      svgo
      fd
      ripgrep
      perl
      gnugrep
      gnused
      findutils
      fastlane
      ffmpeg
      libwebp
      nodejs_26
    ])
    ++ lib.optional isLinux pkgs.stdenv.cc.cc.lib;

  environment = {
    ANDROID_HOME = androidHome;
    ANDROID_SDK_ROOT = androidHome;
    JAVA_HOME = "${pkgs.zulu25}";
    GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${androidHome}/build-tools/${buildToolsVersion}/aapt2";
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "1";
  };

  darwinSystemTools = pkgs.runCommand "darwin-system-tools" { } ''
    mkdir -p $out/bin
    for tool in sysctl sw_vers arch system_profiler; do
      for src in /usr/sbin/$tool /usr/bin/$tool; do
        if [ -e "$src" ]; then
          ln -s "$src" "$out/bin/$tool"
          break
        fi
      done
    done
  '';

in
{
  options.gha-runner.irl.runners = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.tokenFile = lib.mkOption {
          type = lib.types.path;
          description = "Path to file containing the runner's registration token.";
        };
      }
    );
    default = { };
    description = "Infinite-Retry GitHub Actions runners, keyed by runner name.";
  };

  config = lib.mkIf (cfg != { }) {
    services.github-runners = lib.mapAttrs (name: runner: {
      enable = true;
      inherit name;
      url = "https://github.com/Infinite-Retry";
      tokenFile = toString runner.tokenFile;
      replace = true;
      extraLabels = labels;
      extraPackages =
        extraPackages ++ [ androidComposition.androidsdk ] ++ lib.optional isDarwin darwinSystemTools;
      extraEnvironment = environment;
    }) cfg;
  };
}
