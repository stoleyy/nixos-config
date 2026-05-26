# Auto-transcode watch folder: systemd.paths watches /data/transcode/incoming,
# triggers NVENC HEVC encoding via ffmpeg on new files, outputs to /data/transcode/done.
{ pkgs, host, ... }:

let
  transcodeScript = pkgs.writeShellApplication {
    name = "auto-transcode";
    runtimeInputs = [
      pkgs.ffmpeg
      pkgs.findutils
      pkgs.coreutils
    ];
    text = ''
      incoming="${host.dataDir}/transcode/incoming"
      done="${host.dataDir}/transcode/done"
      processing="${host.dataDir}/transcode/processing"

      mkdir -p "$done" "$processing"

      while IFS= read -r -d "" f; do
        base="$(basename "$f")"
        out="$done/''${base%.*}.mp4"

        # Move to processing to avoid re-triggering
        mv "$f" "$processing/$base"

        if ffmpeg -nostdin -y -hwaccel cuda -hwaccel_output_format cuda \
          -i "$processing/$base" \
          -c:v hevc_nvenc -preset p5 -cq 23 \
          -c:a copy -c:s copy \
          "$out"; then
          rm "$processing/$base"
        else
          # On failure, move back to incoming for retry
          mv "$processing/$base" "$incoming/$base"
        fi
      done < <(find "$incoming" -maxdepth 1 -type f \( -name '*.mkv' -o -name '*.avi' -o -name '*.mp4' -o -name '*.ts' \) -print0)
    '';
  };
in
{
  # Watch for new files in the incoming directory.
  # PathModified fires on any modification (new file appearing via mv/cp).
  # PathChanged would miss atomic rename-into-place (systemd.path(5) caveat).
  systemd.paths.transcode-watch = {
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathModified = "${host.dataDir}/transcode/incoming";
      Unit = "transcode.service";
    };
  };

  systemd.services.transcode = {
    description = "NVENC auto-transcode (HEVC)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${transcodeScript}/bin/auto-transcode";
      User = host.user;
      Group = "users";
      Nice = 15;
      IOSchedulingClass = "idle";
    };
  };

  # Ensure directory tree exists.
  systemd.tmpfiles.rules = [
    "d ${host.dataDir}/transcode           0755 ${host.user} users -"
    "d ${host.dataDir}/transcode/incoming   0755 ${host.user} users -"
    "d ${host.dataDir}/transcode/done       0755 ${host.user} users -"
    "d ${host.dataDir}/transcode/processing 0755 ${host.user} users -"
  ];
}
