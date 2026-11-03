# SPDX-License-Identifier: MIT
{ pkgs, coreSrc }:
let
  inherit (pkgs) lib;
  makeGem =
    {
      name,
      version,
      payload,
      platform ? "ruby",
      requirePaths ? [ "lib" ],
      executables ? [ ],
      dependencies ? { },
      summary ? "Prepared Ruby distribution",
      licenses ? [ ],
      requiredRubyVersion ? ">= 0",
    }:
    assert lib.assertMsg (builtins.match "[A-Za-z0-9][A-Za-z0-9_-]*" name != null) "invalid gem name";
    assert lib.assertMsg (builtins.match "[0-9][A-Za-z0-9_.]*" version != null) "invalid gem version";
    pkgs.runCommand "${name}-${version}-gem" { nativeBuildInputs = [ pkgs.ruby ]; } ''
      export HOME="$TMPDIR/gem-home"
      export SOURCE_DATE_EPOCH=1
      mkdir -p "$HOME" root $out
      cp -r ${payload}/. root/
      chmod -R u+w root
      cp ${
        pkgs.writeText "gem.json" (
          builtins.toJSON {
            inherit
              name
              version
              platform
              requirePaths
              executables
              dependencies
              summary
              licenses
              requiredRubyVersion
              ;
          }
        )
      } gem.json
      cat > root/package.gemspec <<'RUBY'
      require 'json'
      config = JSON.parse(File.read('../gem.json'))
      Gem::Specification.new do |s|
        s.name = config['name']; s.version = config['version']
        s.required_ruby_version = config['requiredRubyVersion']
        s.platform = config['platform']; s.summary = config['summary']
        s.authors = ['Package producer']; s.licenses = config['licenses']
        s.files = Dir.glob('**/*', File::FNM_DOTMATCH).select { |f| File.file?(f) && f != 'package.gemspec' }
        s.require_paths = config['requirePaths']; s.executables = config['executables']
        config['dependencies'].each { |name, constraint| s.add_runtime_dependency(name, constraint) }
      end
      RUBY
      cd root
      gem build package.gemspec --output "$out/package.gem"
    '';
in
{
  inherit makeGem;
  package = pkgs.ruby;
}
