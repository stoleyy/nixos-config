{ pkgs, ... }:

{
  # OpenHuman is a CEF AppImage using sharun+uruntime (DwarFS). sharun
  # bundles its own ld-linux + glibc 2.35, completely bypassing nix-ld.
  # CEF's NSS init dlopen's libsoftokn3.so which isn't bundled; the nix-store
  # version needs glibc ≥2.38 (via sqlite). Fix: extract the AppImage once,
  # replace the ENTIRE bundled glibc set (ld-linux + libc + friends) with
  # symlinks to nix-store glibc 2.40, and add the missing NSS + sqlite libs.
  # glibc is backward-compatible so binaries built against 2.35 work on 2.40;
  # the only constraint is ld-linux and libc must be from the same version
  # (GLIBC_PRIVATE ABI). ANGLE→Vulkan clears EGL_BAD_MATCH on RTX 4070 +
  # open kernel module.
  programs.fish.functions.openhuman = {
    description = "openhuman (extracted, nix-ld glibc, ANGLE/Vulkan)";
    body = ''
      set -l appimage ~/.local/bin/openhuman
      set -l extracted ~/.local/share/openhuman-app
      set -l apprun $extracted/AppRun

      # Extract on first run or when the AppImage is newer than the extraction
      if not test -x $apprun; or test $appimage -nt $apprun
        echo "[openhuman] extracting AppImage…"
        rm -rf $extracted
        mkdir -p $extracted
        cd $extracted
        $appimage --appimage-extract 2>/dev/null
        if test -d squashfs-root
          mv squashfs-root/* .
          rm -rf squashfs-root
        end

        # The AppImage bundles its own ld-linux + glibc 2.35. sharun uses
        # that bundled linker, completely bypassing nix-ld. But NSS needs
        # libsoftokn3.so → libsqlite3.so → glibc 2.38+. Fix: replace the
        # ENTIRE glibc set (ld-linux + libc + libm etc.) with nix-store
        # glibc 2.40 so everything is version-consistent. glibc is backward-
        # compatible: libs compiled against 2.35 work on 2.40.
        set -l nix_glibc ${pkgs.glibc}/lib
        set -l glibc_libs ld-linux-x86-64.so.2 libc.so.6 libm.so.6 \
          libpthread.so.0 libdl.so.2 librt.so.1 libresolv.so.2 libmvec.so.1
        for lib in $glibc_libs
          rm -f $extracted/shared/lib/$lib
          if test -e $nix_glibc/$lib
            ln -sf $nix_glibc/$lib $extracted/shared/lib/$lib
          end
        end

        # Add libsoftokn3.so (NSS PKCS#11 soft token — not bundled) and
        # its transitive dep libsqlite3.so.
        ln -sf ${pkgs.nss}/lib/libsoftokn3.so $extracted/shared/lib/libsoftokn3.so
        ln -sf ${pkgs.sqlite.out}/lib/libsqlite3.so.0 $extracted/shared/lib/libsqlite3.so.0
        echo "[openhuman] extraction complete"
        cd -
      end

      $apprun \
        --ozone-platform-hint=auto \
        --use-gl=angle \
        --use-angle=vulkan \
        $argv
    '';
  };
}
