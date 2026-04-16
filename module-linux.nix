{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.gha-runner.irl.runners;

  runnerUser = name: "gha-runner-${name}";
  runnerGroup = "gha-runner";

  gradleProperties = {
    "org.gradle.java.installations.paths" = "${pkgs.zulu21},${pkgs.zulu25}";
    "org.gradle.java.home" = "${pkgs.zulu25}";
    "systemProp.jna.library.path" = lib.makeLibraryPath [ pkgs.udev ];
  };
in
{
  config = lib.mkIf (cfg != { }) {
    sops.secrets = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "gha-runner-${name}-token" {
        owner = runnerUser name;
      }
    ) cfg;

    services.github-runners = lib.mapAttrs (
      name: _: {
        user = runnerUser name;
        group = runnerGroup;
      }
    ) cfg;

    users.users = lib.mapAttrs' (
      name: _:
      lib.nameValuePair (runnerUser name) {
        group = runnerGroup;
        isNormalUser = true;
        linger = true;
        description = "GitHub Actions runner ${name}";
      }
    ) cfg;

    users.groups.${runnerGroup} = { };

    systemd.services = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "github-runner-${name}" {
        serviceConfig.ProtectHome = lib.mkForce false;
        environment.LD_LIBRARY_PATH = lib.makeLibraryPath [
          pkgs.stdenv.cc.cc.lib
          pkgs.udev
        ];
      }
    ) cfg;

    system.activationScripts.ghaRunnerGradleProperties.text =
      let
        gradleFile = pkgs.writeText "gha-runner-gradle.properties" (
          lib.generators.toKeyValue { } gradleProperties
        );
        install = "${pkgs.coreutils}/bin/install";
      in
      lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: _:
          let
            user = runnerUser name;
            gradleDir = "/home/${user}/.gradle";
          in
          ''
            ${install} -d -m 0750 -o ${user} -g ${runnerGroup} ${gradleDir}
            ${install} -m 0640 -o ${user} -g ${runnerGroup} ${gradleFile} ${gradleDir}/gradle.properties
          ''
        ) cfg
      );
  };
}
