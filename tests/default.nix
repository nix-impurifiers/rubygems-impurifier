# SPDX-License-Identifier: MIT
{ pkgs, backend }:
let
  artifact =
    version:
    backend.makeGem {
      name = "impurifier-proof";
      inherit version;
      platform = "x86_64-linux";
      licenses = [ "MIT" ];
      payload =
        pkgs.runCommand "gem-native-${version}"
          {
            nativeBuildInputs = [
              pkgs.stdenv.cc
              pkgs.ruby
            ];
          }
          ''
            mkdir -p $out/lib
            echo '#include <ruby.h>' > proof.c
            echo 'static VALUE value(VALUE self) { return INT2NUM(${version}); }' >> proof.c
            echo 'void Init_impurifier_proof(void) { VALUE m = rb_define_module("ImpurifierProof"); rb_define_singleton_method(m, "value", value, 0); }' >> proof.c
            $CC -shared -fPIC -nostdlib $(ruby -rrbconfig -e 'puts [RbConfig::CONFIG["rubyhdrdir"], RbConfig::CONFIG["rubyarchhdrdir"]].map { |x| "-I"+x }.join(" ")') proof.c -o $out/lib/impurifier_proof.so
          '';
    };
in
{
  native-vm = pkgs.testers.runNixOSTest {
    name = "rubygems-native-extension-lifecycle";
    globalTimeout = 600;
    requiredFeatures = {
      kvm = false;
      devnet = false;
    };
    nodes.machine = { lib, ... }: {
      virtualisation.qemu.package = lib.mkForce pkgs.qemu;
      virtualisation.qemu.forceAccel = false;
      environment.systemPackages = [ backend.package ];
    };
    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      env = "GEM_HOME=/srv/gems GEM_PATH=/srv/gems "
      machine.succeed(env + "gem install --local --no-document ${artifact "1"}/package.gem")
      assert machine.succeed(env + "ruby -rimpurifier_proof -e 'puts ImpurifierProof.value'").strip() == "1"
      machine.succeed(env + "gem install --local --no-document ${artifact "2"}/package.gem")
      assert machine.succeed(env + "ruby -rimpurifier_proof -e 'puts ImpurifierProof.value'").strip() == "2"
      machine.succeed(env + "gem check impurifier-proof")
      machine.succeed(env + "gem uninstall --all --executables --ignore-dependencies impurifier-proof")
      machine.fail(env + "ruby -rimpurifier_proof -e 'puts ImpurifierProof.value'")
      machine.succeed("test ! -e /srv/gems/nix; test -z \"$(find /srv/gems -name impurifier_proof.so)\"")
    '';
  };
}
