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

  buildToolsVersion = "36.0.0";
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    buildToolsVersions = [ buildToolsVersion ];
    platformVersions = [ "36" ];
    platformToolsVersion = "36.0.2";
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
