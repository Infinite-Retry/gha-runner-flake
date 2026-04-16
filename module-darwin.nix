{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.gha-runner.irl.runners;

  gradleProperties = {
    "org.gradle.java.installations.paths" = "${pkgs.zulu21},${pkgs.zulu25}";
    "org.gradle.java.home" = "${pkgs.zulu25}";
  };
in
{
  config = lib.mkIf (cfg != { }) {
    sops.secrets = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "gha-runner-${name}-token" {
        owner = "_github-runner";
      }
    ) cfg;

    system.activationScripts.postActivation.text = ''
      chown _github-runner:_github-runner /var/lib/github-runners

      mkdir -p /var/lib/github-runners/.gradle
      cat > /var/lib/github-runners/.gradle/gradle.properties <<'GRADLE_EOF'
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k}=${v}") gradleProperties)}
      GRADLE_EOF
      chmod 644 /var/lib/github-runners/.gradle/gradle.properties
      chown -R _github-runner:_github-runner /var/lib/github-runners/.gradle
    '';
  };
}
