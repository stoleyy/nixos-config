{
  writeShellApplication,
  coreutils,
  gawk,
  socat,
  jq,
  bc,
  procps,
  android-tools,
  host,
}:
writeShellApplication {
  name = "android-emu-gps";

  runtimeInputs = [
    coreutils
    gawk
    socat
    jq
    bc
    procps
    android-tools
  ];

  text = ''
    EMU_DIR="${host.home}/android-emulator"
    GPS_SOCK="$EMU_DIR/gps-serial.sock"
    PROFILE_DIR="$EMU_DIR/profiles"
    ACTIVE_PROFILE="$EMU_DIR/active-profile"

    mkdir -p "$PROFILE_DIR"

    # ── Built-in location profiles ──
    # Each profile: lat,lon,alt,timezone,locale,dns,proton_region
    declare -A PROFILES=(
      [tokyo]="35.6762,139.6503,40,Asia/Tokyo,ja_JP,8.8.8.8,JP"
      [london]="51.5074,-0.1278,11,Europe/London,en_GB,1.1.1.1,UK"
      [sydney]="-33.8688,151.2093,58,Australia/Sydney,en_AU,1.1.1.1,AU"
      [nyc]="40.7128,-74.0060,10,America/New_York,en_US,9.9.9.9,US-NY"
      [berlin]="52.5200,13.4050,34,Europe/Berlin,de_DE,9.9.9.9,DE"
      [seoul]="37.5665,126.9780,38,Asia/Seoul,ko_KR,8.8.8.8,KR"
      [saopaulo]="-23.5505,-46.6333,760,America/Sao_Paulo,pt_BR,9.9.9.9,BR"
    )

    # Load custom profiles from $PROFILE_DIR/*.json
    load_custom_profiles() {
      for f in "$PROFILE_DIR"/*.json; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .json)
        lat=$(jq -r '.lat' "$f")
        lon=$(jq -r '.lon' "$f")
        alt=$(jq -r '.alt // 0' "$f")
        tz=$(jq -r '.timezone' "$f")
        locale=$(jq -r '.locale // "en_US"' "$f")
        dns=$(jq -r '.dns // "9.9.9.9"' "$f")
        region=$(jq -r '.proton_region // "US"' "$f")
        PROFILES[$name]="$lat,$lon,$alt,$tz,$locale,$dns,$region"
      done
    }
    load_custom_profiles

    usage() {
      echo "Usage: android-emu-gps [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --profile NAME        Apply a location profile (sets GPS + VPN + tz + locale)"
      echo "  --lat NUM --lon NUM   Set GPS coordinates directly"
      echo "  --alt NUM             Altitude in meters (default: 0)"
      echo "  --speed NUM           Speed in m/s (default: 0)"
      echo "  --heading NUM         Heading in degrees (default: 0)"
      echo "  --gpx FILE            Replay a GPX route file"
      echo "  --list-profiles       List available location profiles"
      echo "  --stop                Stop the GPS feed"
      echo ""
      echo "Profiles set ALL of: GPS coords, VPN server region, timezone, locale, DNS."
      echo "Custom profiles: place JSON files in $PROFILE_DIR/"
      echo ""
      echo "Example custom profile ($PROFILE_DIR/paris.json):"
      echo '  {"lat":48.8566,"lon":2.3522,"alt":35,"timezone":"Europe/Paris","locale":"fr_FR","dns":"9.9.9.9","proton_region":"FR"}'
      exit 1
    }

    # ── NMEA 0183 sentence generation ──

    # XOR checksum for NMEA sentences (byte-wise XOR of every character).
    nmea_checksum() {
      printf '%s' "$1" | od -An -tu1 | awk '{for(i=1;i<=NF;i++) cs=xor(cs,$i)} END{printf "%02X",cs}'
    }

    # Convert decimal degrees to NMEA DDMM.MMMM format.
    deg_to_nmea() {
      local deg="$1" width="$2"
      local abs_deg int_deg minutes nmea
      abs_deg=$(echo "$deg" | awk '{printf "%.10f", ($1 < 0) ? -$1 : $1}')
      int_deg=$(echo "$abs_deg" | awk '{printf "%d", $1}')
      minutes=$(echo "$abs_deg $int_deg" | awk '{printf "%07.4f", ($1 - $2) * 60}')
      nmea=$(printf "%0''${width}d%s" "$int_deg" "$minutes")
      echo "$nmea"
    }

    # Determine N/S and E/W directions.
    lat_dir() { if (( $(echo "$1 < 0" | bc -l) )); then echo "S"; else echo "N"; fi; }
    lon_dir() { if (( $(echo "$1 < 0" | bc -l) )); then echo "W"; else echo "E"; fi; }

    # GPGGA — GPS fix data.
    make_gga() {
      local lat="$1" lon="$2" alt="$3"
      local time
      time=$(date -u +%H%M%S.00)
      local nlat nlon ld nd
      nlat=$(deg_to_nmea "$lat" 2)
      nlon=$(deg_to_nmea "$lon" 3)
      ld=$(lat_dir "$lat")
      nd=$(lon_dir "$lon")
      local body="GPGGA,$time,$nlat,$ld,$nlon,$nd,1,08,0.9,$alt,M,0.0,M,,"
      local cs
      cs=$(nmea_checksum "$body")
      echo "\$''${body}*''${cs}"
    }

    # GPRMC — recommended minimum navigation data.
    make_rmc() {
      local lat="$1" lon="$2" speed="$3" heading="$4"
      local time date_str
      time=$(date -u +%H%M%S.00)
      date_str=$(date -u +%d%m%y)
      local nlat nlon ld nd
      nlat=$(deg_to_nmea "$lat" 2)
      nlon=$(deg_to_nmea "$lon" 3)
      ld=$(lat_dir "$lat")
      nd=$(lon_dir "$lon")
      local speed_knots
      speed_knots=$(echo "$speed" | awk '{printf "%.1f", $1 * 1.944}')
      local body="GPRMC,$time,A,$nlat,$ld,$nlon,$nd,$speed_knots,$heading,$date_str,,,"
      local cs
      cs=$(nmea_checksum "$body")
      echo "\$''${body}*''${cs}"
    }

    # GPGSV — satellites in view (plausible fake data: 8 satellites).
    make_gsv() {
      local body="GPGSV,1,1,08,01,40,083,45,02,17,308,44,03,57,162,42,04,25,245,40"
      local cs
      cs=$(nmea_checksum "$body")
      echo "\$''${body}*''${cs}"
    }

    # ── Medtronic CardioSync stent identity ──
    apply_stent_identity() {
      echo "Applying Medtronic CardioSync stent identity..."
      local props=(
        "ro.product.manufacturer=Medtronic"
        "ro.product.model=CardioSync™ Stent Monitor v3.7"
        "ro.product.device=implant-unit-0x4F2A"
        "ro.product.brand=Medtronic Cardiac Solutions"
        "ro.build.display.id=STENT-OS 2.1.4 / FDA-510(k) K247831 / REL-KEYS"
        "ro.build.description=cardiosync-monitor userdebug 14 STENT.240301.007 release-keys"
        "ro.build.fingerprint=Medtronic/CardioSync/implant-unit-0x4F2A:14/STENT.240301.007/release-keys"
        "ro.hardware=biotelemetry-soc"
        "ro.serialno=MDT-IMPLANT-2024-8837201"
        "ro.product.board=titanium-mesh-rv2"
        "gsm.operator.alpha=Medtronic BodyNet"
        "gsm.sim.operator.alpha=BodyNet LTE-M"
        "ro.kernel.qemu=0"
        "ro.boot.hardware=biotelemetry-soc"
        "status.battery.level=73"
        "status.battery.state=3"
      )
      for prop in "''${props[@]}"; do
        adb shell setprop "''${prop%%=*}" "''${prop#*=}" 2>/dev/null || true
      done
      local new_adid
      new_adid=$(cat /proc/sys/kernel/random/uuid)
      adb shell settings put secure advertising_id "$new_adid" 2>/dev/null || true
      echo "Stent identity applied. Ad ID: $new_adid"
    }

    # ── GPS feed via virtio-serial socket ──
    feed_gps() {
      local lat="$1" lon="$2" alt="''${3:-0}" speed="''${4:-0}" heading="''${5:-0}"

      if [ ! -S "$GPS_SOCK" ]; then
        echo "ERROR: GPS serial socket not found at $GPS_SOCK"
        echo "Is the VM running? Try: android-emu-start start"
        exit 1
      fi

      echo "Feeding GPS: lat=$lat lon=$lon alt=$alt speed=$speed heading=$heading"
      echo "Press Ctrl+C to stop."

      while true; do
        {
          make_gga "$lat" "$lon" "$alt"
          make_rmc "$lat" "$lon" "$speed" "$heading"
          make_gsv
        } | socat - UNIX-CONNECT:"$GPS_SOCK" 2>/dev/null || {
          echo "GPS socket disconnected. Retrying in 2s..."
          sleep 2
          continue
        }
        sleep 1
      done
    }

    # ── GPX route replay ──
    replay_gpx() {
      local gpx_file="$1"
      local replay_speed="''${2:-1.0}"

      if [ ! -f "$gpx_file" ]; then
        echo "ERROR: GPX file not found: $gpx_file"
        exit 1
      fi

      echo "Replaying GPX route: $gpx_file (speed multiplier: $replay_speed)"

      local points
      points=$(awk -F'[="<>]' '/<trkpt/{lat="";lon="";for(i=1;i<=NF;i++){if($i~/ lat/)lat=$(i+1);if($i~/ lon/)lon=$(i+1)}} /<ele>/{ele=$(NF-1)} /<\/trkpt>/{if(lat!=""&&lon!="")print lat","lon","(ele?ele:0)}' "$gpx_file")

      local prev_lat="" prev_lon=""
      while IFS=, read -r lat lon alt; do
        if [ -n "$prev_lat" ]; then
          local heading
          heading=$(echo "$prev_lat $prev_lon $lat $lon" | awk '{
            dlat=$3-$1; dlon=$4-$2;
            h=atan2(dlon,dlat)*180/3.14159265;
            if(h<0) h+=360;
            printf "%.1f",h
          }')
          local dist
          dist=$(echo "$prev_lat $prev_lon $lat $lon" | awk '{
            dlat=($3-$1)*111320; dlon=($4-$2)*111320*cos($1*3.14159265/180);
            printf "%.2f", sqrt(dlat*dlat+dlon*dlon)
          }')
          local speed
          speed=$(echo "$dist $replay_speed" | awk '{printf "%.1f", $1 * $2}')

          {
            make_gga "$lat" "$lon" "$alt"
            make_rmc "$lat" "$lon" "$speed" "$heading"
            make_gsv
          } | socat - UNIX-CONNECT:"$GPS_SOCK" 2>/dev/null || true
        fi
        prev_lat="$lat"
        prev_lon="$lon"
        sleep "$(echo "1 $replay_speed" | awk '{printf "%.2f", $1 / $2}')"
      done <<< "$points"

      echo "GPX replay complete."
    }

    # ── Profile application ──
    apply_profile() {
      local name="$1"
      local profile_data="''${PROFILES[$name]:-}"

      if [ -z "$profile_data" ]; then
        echo "ERROR: Unknown profile '$name'."
        echo "Available profiles: ''${!PROFILES[*]}"
        exit 1
      fi

      IFS=',' read -r lat lon alt tz locale dns region <<< "$profile_data"

      echo "=== Applying profile: $name ==="
      echo "  GPS:      $lat, $lon (alt: $alt m)"
      echo "  Timezone: $tz"
      echo "  Locale:   $locale"
      echo "  DNS:      $dns"
      echo "  VPN:      Proton $region"

      echo "$name" > "$ACTIVE_PROFILE"

      apply_stent_identity

      adb shell service call alarm 3 s16 "$tz" 2>/dev/null || true
      adb shell setprop persist.sys.language "''${locale%%_*}" 2>/dev/null || true
      adb shell setprop persist.sys.country "''${locale##*_}" 2>/dev/null || true

      echo ""
      echo "Starting GPS feed (Ctrl+C to stop)..."
      feed_gps "$lat" "$lon" "$alt" "0" "0"
    }

    list_profiles() {
      echo "Available location profiles:"
      echo ""
      printf "  %-12s %-22s %-20s %s\n" "NAME" "COORDINATES" "TIMEZONE" "REGION"
      printf "  %-12s %-22s %-20s %s\n" "----" "-----------" "--------" "------"
      for name in $(echo "''${!PROFILES[*]}" | tr ' ' '\n' | sort); do
        IFS=',' read -r lat lon alt tz locale dns region <<< "''${PROFILES[$name]}"
        printf "  %-12s %-22s %-20s %s\n" "$name" "$lat, $lon" "$tz" "$region"
      done
      echo ""
      echo "Custom profiles: place JSON in $PROFILE_DIR/"
      if [ -f "$ACTIVE_PROFILE" ]; then
        echo "Active profile: $(cat "$ACTIVE_PROFILE")"
      fi
    }

    stop_feed() {
      pkill -f "socat.*$GPS_SOCK" 2>/dev/null || true
      rm -f "$ACTIVE_PROFILE"
      echo "GPS feed stopped."
    }

    # ── Argument parsing ──
    LAT="" LON="" ALT="0" SPEED="0" HEADING="0" PROFILE="" GPX=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --profile)       PROFILE="$2"; shift 2 ;;
        --lat)           LAT="$2"; shift 2 ;;
        --lon)           LON="$2"; shift 2 ;;
        --alt)           ALT="$2"; shift 2 ;;
        --speed)         SPEED="$2"; shift 2 ;;
        --heading)       HEADING="$2"; shift 2 ;;
        --gpx)           GPX="$2"; shift 2 ;;
        --list-profiles) list_profiles; exit 0 ;;
        --stop)          stop_feed; exit 0 ;;
        --help|-h)       usage ;;
        *)               echo "Unknown option: $1"; usage ;;
      esac
    done

    if [ -n "$PROFILE" ]; then
      apply_profile "$PROFILE"
    elif [ -n "$GPX" ]; then
      replay_gpx "$GPX" "$SPEED"
    elif [ -n "$LAT" ] && [ -n "$LON" ]; then
      feed_gps "$LAT" "$LON" "$ALT" "$SPEED" "$HEADING"
    else
      usage
    fi
  '';
}
