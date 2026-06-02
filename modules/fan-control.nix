# Fan control — out-of-tree it87 driver (IT8637E) + fancontrol service for the Predator PO3-650.
{
  pkgs,
  config,
  ...
}:

let
  # Out-of-tree it87 driver (frankcrawford fork) — supports newer ITE chips
  # including IT8637E on the Predator PO3-650 via force_id
  it87 = config.boot.kernelPackages.callPackage (
    {
      stdenv,
      lib,
      fetchFromGitHub,
      kernel,
    }:
    stdenv.mkDerivation {
      pname = "it87";
      version = "unstable-2026-05-22";

      src = fetchFromGitHub {
        owner = "frankcrawford";
        repo = "it87";
        rev = "20f2f2f4c92c14fcdd26f60d050e693ad2c30bf8";
        hash = "sha256-o2riPbm75Bez4/SrGV7hB3mlqdxxrwRPdre+3W5y/I0=";
      };

      nativeBuildInputs = kernel.moduleBuildDependencies;

      makeFlags = [
        "TARGET=${kernel.modDirVersion}"
        "KERNEL_BUILD=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
        "KERNEL_MODULES=$(out)/lib/modules/${kernel.modDirVersion}"
      ];

      installPhase = ''
        install -D it87.ko $out/lib/modules/${kernel.modDirVersion}/extra/it87.ko
      '';

      meta.license = lib.licenses.gpl2Plus;
    }
  ) { };

  fanShowScript = pkgs.writeShellScriptBin "fan-show" ''
    set -euo pipefail
    echo "=== Thermal zones ==="
    for tz in /sys/class/thermal/thermal_zone*/; do
      type=$(cat "''${tz}type" 2>/dev/null || echo "?")
      temp=$(cat "''${tz}temp" 2>/dev/null || echo "0")
      echo "  $(basename "$tz") ($type): $((temp / 1000))°C"
    done
    echo
    echo "=== PWM fan control ==="
    for hwmon in /sys/class/hwmon/hwmon*/; do
      name=$(cat "''${hwmon}name" 2>/dev/null || echo "?")
      for pwm in "''${hwmon}"pwm*_enable; do
        [ -f "$pwm" ] || continue
        base=$(basename "$pwm" | sed 's/_enable//')
        val=$(cat "''${hwmon}''${base}" 2>/dev/null || echo "?")
        enable=$(cat "$pwm" 2>/dev/null || echo "?")
        echo "  $name/$base: value=$val enable=$enable"
      done
      for fan in "''${hwmon}"fan*_input; do
        [ -f "$fan" ] || continue
        base=$(basename "$fan")
        rpm=$(cat "$fan" 2>/dev/null || echo "?")
        echo "  $name/$base: ''${rpm} RPM"
      done
    done
    echo
    echo "=== ACPI Fan states ==="
    for i in 24 25 26 27 28; do
      cur=$(cat "/sys/class/thermal/cooling_device$i/cur_state" 2>/dev/null || echo "?")
      echo "  cooling_device$i: state=$cur"
    done
    echo
    echo "=== Trip points (thermal_zone0 / acpitz) ==="
    TZ="/sys/class/thermal/thermal_zone0"
    for i in 0 1 2 3 4 5; do
      temp=$(cat "$TZ/trip_point_''${i}_temp" 2>/dev/null || echo "0")
      type=$(cat "$TZ/trip_point_''${i}_type" 2>/dev/null || echo "?")
      echo "  trip_point_$i: $((temp / 1000))°C ($type)"
    done
  '';
in
{
  # Out-of-tree it87 driver for ITE IT8637E Super I/O chip (fan PWM control)
  # The IT8637E is not in the upstream kernel driver; we force-load it as IT8628E
  # which is register-compatible (confirmed working on ODROID-H3 with same chip).
  boot = {
    extraModulePackages = [
      config.boot.kernelPackages.acpi_call
      it87
    ];
    kernelModules = [
      "acpi_call"
      "it87"
    ];

    # Load it87 with force_id to recognize the IT8637E as IT8628E
    extraModprobeConfig = ''
      options it87 force_id=0x8628 ignore_resource_conflict=1
    '';

    # acpi_enforce_resources=lax: let it87 claim I/O ports held by ACPI PNP.
    # iomem=relaxed was removed: it87 + fancontrol use sysfs (kernel ioport API),
    # not /dev/mem. The only things that needed iomem=relaxed were the diagnostic
    # scripts/enable-ften*.sh (manual /dev/mem writes) which are not production config.
    kernelParams = [
      "acpi_enforce_resources=lax"
    ];
  };

  # Fan curves are managed by CoolerControl (programs.coolercontrol in base.nix)
  # which also uses hwmon2 (it8628). hardware.fancontrol is intentionally absent —
  # both services writing to the same PWM channels simultaneously would fight.

  # Hardware monitoring tools
  environment.systemPackages = [
    fanShowScript
    pkgs.lm_sensors
    pkgs.acpica-tools # iasl for DSDT decompilation
    pkgs.nbfc-linux # ec_probe for EC register discovery
    pkgs.stress-ng # CPU stress testing for fan register diffing
  ];

  # libsensors display cleanup for the IT8637E (force-loaded as IT8628E above).
  # The force_id mismatch leaves the chip's voltage scaling and most temp pins
  # mismapped, so `sensors` reports garbage — the +3.3V rail as 4.46 V, temp6 as
  # -41 °C, and nonsensical min/max thresholds (high < low) firing false ALARMs.
  # The chip is kept ONLY for fan PWM; CoolerControl reads raw hwmon sysfs and is
  # NOT affected by this file. Hide the bogus sense channels so `sensors` (and
  # anything using libsensors) stops crying wolf — coretemp / nvidia-smi / nvme
  # are the authoritative temps. Real fan tachometers (fan1-3) are kept; fan4/5
  # are empty headers. Wildcard the ISA address in case it re-bases.
  environment.etc."sensors.d/predator.conf".text = ''
    chip "it8628-isa-*"
        # Misscaled voltage rails (all read implausibly; min>max thresholds).
        ignore in0
        ignore in1
        ignore in2
        ignore in3
        ignore in4
        ignore in5
        ignore in6
        ignore in7
        ignore in8
        # Mismapped temp pins (incl. temp6 = -41 °C) — unreliable under force_id.
        # If a stress-test later proves a specific tempN tracks a real board/VRM
        # sensor, drop its `ignore` line to bring just that one back.
        ignore temp1
        ignore temp2
        ignore temp3
        ignore temp4
        ignore temp5
        ignore temp6
        # Empty fan headers + floating chassis-intrusion pin.
        ignore fan4
        ignore fan5
        ignore intrusion0
  '';
}
