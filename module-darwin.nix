{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.gha-runner.irl.runners;
  xcodeCfg = config.gha-runner.irl.darwin.xcode;

  gradleProperties = {
    "org.gradle.java.installations.paths" = "${pkgs.zulu21},${pkgs.zulu25}";
    "org.gradle.java.home" = "${pkgs.zulu25}";
  };

  xcodeAppPath = "${xcodeCfg.directory}/Xcode-${xcodeCfg.version}.app";
  xcodeDeveloperDir = "${xcodeAppPath}/Contents/Developer";
  xcodeBuildPath = "${xcodeDeveloperDir}/usr/bin/xcodebuild";
  xcodesInstallCommand = ''
    ${lib.getExe' pkgs.xcodes "xcodes"} install ${lib.escapeShellArg xcodeCfg.version} \
      --directory ${lib.escapeShellArg xcodeCfg.directory} \
      --empty-trash \
      --experimental-unxip \
      --select \
      ${lib.optionalString (xcodeCfg.fastlaneSessionFile != null) "--use-fastlane-auth"}
  '';

  xcodeRunnerTools = pkgs.runCommandLocal "gha-runner-xcode-tools" { } ''
        mkdir -p $out/bin

        for tool in xcodebuild xcrun simctl actool ibtool xctrace; do
          cat > "$out/bin/$tool" <<EOF
    #!${pkgs.bash}/bin/bash
    export DEVELOPER_DIR=${lib.escapeShellArg xcodeDeveloperDir}
    exec ${lib.escapeShellArg "${xcodeDeveloperDir}/usr/bin/$tool"} "\$@"
    EOF
          chmod +x "$out/bin/$tool"
        done

        cat > "$out/bin/xcode-select" <<'EOF'
    #!${pkgs.bash}/bin/bash
    exec /usr/bin/xcode-select "$@"
    EOF
        chmod +x "$out/bin/xcode-select"
  '';
in
{
  options.gha-runner.irl.darwin.xcode = {
    version = lib.mkOption {
      type = lib.types.str;
      default = "26.2.0";
      description = "Xcode version to keep installed for Darwin GitHub Actions runners.";
    };

    directory = lib.mkOption {
      type = lib.types.str;
      default = "/Applications";
      description = "Directory where xcodes installs Xcode.";
    };

    usernameFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        File containing the Apple ID username for xcodes.
        Only needed when the requested Xcode is not already installed and xcodes
        has not already been authenticated via the system keychain.
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        File containing the Apple ID password for xcodes.
        Only needed when the requested Xcode is not already installed and xcodes
        has not already been authenticated via the system keychain.
      '';
    };

    fastlaneSessionFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        File containing a FASTLANE_SESSION value for non-interactive xcodes
        installs. When set, the activation hook installs Xcode with
        `xcodes --use-fastlane-auth`.
      '';
    };
  };

  config = lib.mkIf (cfg != { }) {
    sops.secrets = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "gha-runner-${name}-token" {
        owner = "_github-runner";
      }
    ) cfg;

    services.github-runners = lib.mapAttrs (_: _: {
      extraEnvironment = {
        DEVELOPER_DIR = xcodeDeveloperDir;
        XCODE_APP_PATH = xcodeAppPath;
        XCODE_DEVELOPER_DIR = xcodeDeveloperDir;
      };
      extraPackages = [ xcodeRunnerTools ];
    }) cfg;

    system.activationScripts.postActivation.text = ''
      chown _github-runner:_github-runner /var/lib/github-runners

      mkdir -p /var/lib/github-runners/.gradle
      cat > /var/lib/github-runners/.gradle/gradle.properties <<'GRADLE_EOF'
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k}=${v}") gradleProperties)}
      GRADLE_EOF
      chmod 644 /var/lib/github-runners/.gradle/gradle.properties
      chown -R _github-runner:_github-runner /var/lib/github-runners/.gradle

      if [ ! -d ${lib.escapeShellArg xcodeAppPath} ]; then
        export PATH=${lib.escapeShellArg "${
          lib.makeBinPath [
            pkgs.xcodes
            pkgs.coreutils
          ]
        }:/usr/bin:/bin:/usr/sbin:/sbin"}

        ${
          if xcodeCfg.fastlaneSessionFile != null then
            ''
              FASTLANE_SESSION="$(${pkgs.coreutils}/bin/tr -d '\n' < ${lib.escapeShellArg (toString xcodeCfg.fastlaneSessionFile)})"
              export FASTLANE_SESSION
              ${xcodesInstallCommand}
            ''
          else if xcodeCfg.usernameFile != null && xcodeCfg.passwordFile != null then
            ''
              XCODES_USERNAME="$(${pkgs.coreutils}/bin/tr -d '\n' < ${lib.escapeShellArg (toString xcodeCfg.usernameFile)})"
              export XCODES_USERNAME
              XCODES_PASSWORD="$(${pkgs.coreutils}/bin/tr -d '\n' < ${lib.escapeShellArg (toString xcodeCfg.passwordFile)})"
              export XCODES_PASSWORD
              ${xcodesInstallCommand}
            ''
          else
            ''
              echo >&2 "Xcode ${xcodeCfg.version} is missing at ${xcodeAppPath} and no xcodes credentials are configured."
              echo >&2 "Configure gha-runner.irl.darwin.xcode.fastlaneSessionFile or both usernameFile and passwordFile, or pre-install Xcode ${xcodeCfg.version}."
              exit 1
            ''
        }
      fi

      /usr/bin/xcode-select --switch ${lib.escapeShellArg xcodeDeveloperDir}

      if ! ${lib.escapeShellArg xcodeBuildPath} -checkFirstLaunchStatus >/dev/null 2>&1; then
        ${lib.escapeShellArg xcodeBuildPath} -runFirstLaunch
      fi
    '';
  };
}
