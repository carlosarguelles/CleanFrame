{
  description = "CleanFrame with the Tizen web CLI, certificate tools and SDB";

  nixConfig = {
    allowUnfree = true;
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    tizen.url = "github:griffi-gh/nix-tizen-sdk";
  };

  outputs = { self, nixpkgs, tizen }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      tizenPkgs = tizen.legacyPackages.${system};
      # nix-tizen-sdk's mkTizenSdk writes sdk.version through a store symlink and
      # fails with "Permission denied". Join the same packages here and replace
      # that symlink with a regular file. Also copy the CLI scripts: tizen.sh
      # resolves symlinks, then looks for the JDK beside the real script.
      tizenSdk =
        let
          os = "ubuntu-64";
          dist = tizenPkgs.tizen-sdk-distribution.official.Tizen_SDK_10_0.${os};
          wrappers = tizenPkgs.tizen-sdk.wrapper or { };
          get = name: wrappers.${name} or dist.${name};
          components = [
            "COMMON-MANDATORY"
            "COMMON-CLI"
            "COMMON-WEB-DA"
            "TIZEN-9_0-WebAppDevelopment-CLI"
            "WebCLI"
            "certificate-manager-product"
            "certificate-generator"
            "sdb"
          ];
          all = builtins.genericClosure {
            startSet = map (pkg: { key = pkg; val = get pkg; }) components;
            operator = item: map (pkg: { key = pkg; val = get pkg; }) (item.val.tizenDependencies or [ ]);
          };
        in
        pkgs.symlinkJoin {
          name = "tizen-sdk-10.0";
          paths = map (item: item.val) all;
          postBuild = ''
            mkdir -p "$out/opt/tizen-studio-data"
            rm -f "$out/opt/tizen-studio/sdk.info" "$out/opt/tizen-studio/sdk.version"
            cat > "$out/opt/tizen-studio/sdk.info" <<EOF
            TIZEN_SDK_INSTALLED_PATH=$out/opt/tizen-studio
            TIZEN_SDK_DATA_PATH=$out/opt/tizen-studio-data
            EOF
            printf '%s\n' 'TIZEN_SDK_VERSION=10.0' > "$out/opt/tizen-studio/sdk.version"
            bin="$out/opt/tizen-studio/tools/ide/bin"
            for name in tizen tizen.sh; do
              target=$(readlink -f "$bin/$name")
              rm -f "$bin/$name"
              cp "$target" "$bin/$name"
              chmod 755 "$bin/$name"
            done
          '';
        };
    in
    {
      packages.${system}.default = tizenSdk;
      devShells.${system}.default = pkgs.mkShell {
        packages = [ tizenSdk ];
        # The store tree is read-only and its JARs are symlinks, so the CLI
        # cannot find sdk.info or write its config there. Keep one writable copy.
        shellHook = ''
          dest="''${XDG_DATA_HOME:-$HOME/.local/share}/cleanframe/tizen-studio"
          data="''${XDG_DATA_HOME:-$HOME/.local/share}/cleanframe/tizen-studio-data"
          if [ ! -x "$dest/tools/ide/bin/tizen" ]; then
            mkdir -p "$dest" "$data"
            cp -aL ${tizenSdk}/opt/tizen-studio/. "$dest/"
            chmod -R u+w "$dest"
          fi
          mkdir -p "$data"
          cat > "$dest/sdk.info" <<EOF
          TIZEN_SDK_INSTALLED_PATH=$dest
          TIZEN_SDK_DATA_PATH=$data
          JDK_PATH=$dest/jdk
          EOF
          printf '%s\n' 'TIZEN_SDK_VERSION=10.0' > "$dest/sdk.version"
          export PATH="$dest/tools/ide/bin:$dest/tools:$PATH"
        '';
      };
    };
}
