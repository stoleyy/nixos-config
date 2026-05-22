{
  pkgs,
  lib,
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
  boot.extraModulePackages = [
    config.boot.kernelPackages.acpi_call
    it87
  ];
  boot.kernelModules = [
    "acpi_call"
    "it87"
  ];

  # Load it87 with force_id to recognize the IT8637E as IT8628E
  boot.extraModprobeConfig = ''
    options it87 force_id=0x8628 ignore_resource_conflict=1
  '';

  # acpi_enforce_resources=lax: let it87 claim I/O ports held by ACPI PNP.
  # iomem=relaxed was removed: it87 + fancontrol use sysfs (kernel ioport API),
  # not /dev/mem. The only things that needed iomem=relaxed were the diagnostic
  # scripts/enable-ften*.sh (manual /dev/mem writes) which are not production config.
  boot.kernelParams = [
    "acpi_enforce_resources=lax"
  ];

  # Fan curve: silent ≤45°C, linear ramp 50–80°C, full speed ≥80°C
  # pwm1/2/3 = chassis fans driven by CPU package temp; pwm4 left in BIOS auto
  hardware.fancontrol.enable = true;
  hardware.fancontrol.config = ''
    INTERVAL=5
    DEVPATH=hwmon2=devices/platform/it87.1840 hwmon6=devices/platform/coretemp.0
    DEVNAME=hwmon2=it8628 hwmon6=coretemp
    FCTEMPS=hwmon2/pwm1=hwmon6/temp1_input hwmon2/pwm2=hwmon6/temp1_input hwmon2/pwm3=hwmon6/temp1_input
    FCFANS=hwmon2/pwm1=hwmon2/fan1_input hwmon2/pwm2=hwmon2/fan2_input hwmon2/pwm3=hwmon2/fan3_input
    MINTEMP=hwmon2/pwm1=45 hwmon2/pwm2=45 hwmon2/pwm3=45
    MAXTEMP=hwmon2/pwm1=80 hwmon2/pwm2=80 hwmon2/pwm3=80
    MINSTART=hwmon2/pwm1=80 hwmon2/pwm2=80 hwmon2/pwm3=80
    MINSTOP=hwmon2/pwm1=20 hwmon2/pwm2=20 hwmon2/pwm3=20
    MINPWM=hwmon2/pwm1=20 hwmon2/pwm2=20 hwmon2/pwm3=20
    MAXPWM=hwmon2/pwm1=255 hwmon2/pwm2=255 hwmon2/pwm3=255
  '';

  # Hardware monitoring tools
  environment.systemPackages = [
    fanShowScript
    pkgs.lm_sensors
    pkgs.acpica-tools # iasl for DSDT decompilation
    pkgs.nbfc-linux # ec_probe for EC register discovery
    pkgs.stress-ng # CPU stress testing for fan register diffing
  ];
}
