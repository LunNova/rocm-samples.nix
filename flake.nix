{
  # Usage
  # nix shell .#inference --accept-flake-config
  # nix shell .#torch --accept-flake-config

  inputs = {
    nixpkgs.url = "github:LunNova/nixpkgs/8e003751caebc353c433e8b59ecb2e5ca5371105";
    flake-utils.url = "github:numtide/flake-utils";
  };

  nixConfig = {
    extra-substituters = [ "https://hoshitsuki-nixos.pegasus-vibes.ts.net/rocm" ];
    extra-trusted-public-keys = [ "rocm:ZHNsJO/jx9T2CVUHQj6GMSYteDx8OQZYA2uf/PsEM8w=" ];
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachSystem flake-utils.lib.defaultSystems (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        self = {
          devShells.default = self.devShells.inference;
          devShells.torch = pkgs.mkShellNoCC {
            ROCM_PATH = pkgs.pkgsRocm.rocmPackages.meta.rocm-all;
            TORCHINDUCTOR_FX_GRAPH_CACHE = 1;
            TORCHINDUCTOR_AUTOGRAD_CACHE = 1;
            HSA_TOOLS_REPORT_LOAD_FAILURE = 1;
            HSA_VEN_AMD_AQLPROFILE_LOG = 1;
            buildInputs = with pkgs.pkgsRocm; [
              pkg-config
              rocmPackages.rocminfo
              rocmPackages.rocprofiler
              rocmPackages.ck4inductor
              rocmPackages.llvm.rocmcxx
              python3Packages.torch
              # TODO: get bitsandbytes to work with ROCm since it's popular
            ];
            shellHook = ''
              # Persist cache dirs for triton/torch/miopen
              # to avoid them defaulting to a transient tmpdir created for the nix shell
              export TRITON_CACHE_DIR=$HOME/ml-cache/triton
              export TORCHINDUCTOR_CACHE_DIR=$HOME/ml-cache/torchinductor
              export MIOPEN_USER_DB_PATH=$HOME/ml-cache/miopen
              mkdir -p $TRITON_CACHE_DIR $TORCHINDUCTOR_CACHE_DIR $MIOPEN_USER_DB_PATH
            '';
          };
          # TODO: huggingface transformers inference?
          devShells.vllm = pkgs.mkShellNoCC {
            buildInputs = with pkgs; [
              rocmPackages.rocminfo
              rocmPackages.rocprofiler
              # pkgsRocm.vllm # FIXME: nixpkgs vllm only supports CUDA currently
            ];
          };
          devShells.inference = pkgs.mkShellNoCC {
            buildInputs = with pkgs; [
              rocmPackages.rocminfo
              rocmPackages.rocprofiler
              # top level alias for ollama with rocm support exists
              ollama-rocm
              # need config.enableRocm for llama-cpp
              pkgsRocm.llama-cpp
              # pkgsRocm.local-ai # FIXME: llama-cpp-grpc build as dep of this fails
            ];
          };
          formatter = pkgs.treefmt.withConfig {
            runtimeInputs = with pkgs; [
              nixfmt-rfc-style
            ];
            settings = {
              tree-root-file = ".git/index";
              formatter = {
                nixfmt = {
                  command = "nixfmt";
                  includes = [ "*.nix" ];
                };
              };
            };
          };
          # attic push rocm (nix build --no-link --print-out-paths .#checks.x86_64-linux.all)
          checks.all = pkgs.stdenv.mkDerivation {
            name = "all-components";
            dontUnpack = true;
            postBuild = ''
              echo "${pkgs.lib.concatStringsSep "\n" (builtins.attrValues self.devShells)}" > $out
            '';
          };
        };
      in
      self
    );
}
