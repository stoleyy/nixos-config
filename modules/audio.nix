{ ... }:

{
  services.pulseaudio.enable = false;
  security.rtkit.enable      = true;

  services.pipewire = {
    enable             = true;
    alsa.enable        = true;
    alsa.support32Bit  = true;
    pulse.enable       = true;
    jack.enable        = true;

    # High-quality Bluetooth audio codecs — wireless headphones get LDAC / aptX
    # / AAC where supported instead of vanilla SBC; headsets get wideband mSBC.
    wireplumber.extraConfig.bluetoothEnhancements = {
      "monitor.bluez.properties" = {
        "bluez5.enable-sbc-xq"    = true;
        "bluez5.enable-msbc"      = true;
        "bluez5.enable-hw-volume" = true;
        "bluez5.roles"            = [ "hsp_hs" "hsp_ag" "hfp_hf" "hfp_ag" "a2dp_sink" "a2dp_source" ];
      };
    };

    # Bit-exact playback for the G80SD's HDMI sink (and any other DACs).
    # Default config locks PipeWire to 48 kHz and resamples everything else,
    # which is audible on Spotify FLAC, Tidal Hi-Res, and high-rate music in
    # mpv. allowed-rates lets PipeWire match the source rate when the active
    # stream is bit-exact-capable. Quantum range covers low-latency games at
    # the small end and stable music DAC behaviour at the large end.
    extraConfig.pipewire."92-clock" = {
      "context.properties" = {
        "default.clock.rate"          = 48000;
        "default.clock.allowed-rates" = [ 44100 48000 88200 96000 176400 192000 ];
        "default.clock.quantum"       = 1024;
        "default.clock.min-quantum"   = 32;
        "default.clock.max-quantum"   = 8192;
      };
    };
  };
}
