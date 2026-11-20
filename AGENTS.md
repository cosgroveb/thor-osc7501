# Project guide

`thor-osc7501` is an opt-in OSC 7501 reporter for Thor commands.
Target MRI Ruby >= 2.1 and Thor >= 0.19.4. Runtime dependencies stay limited to Thor.

- `lib/thor/osc7501.rb` activates reporting for Thor.
- `lib/thor/osc7501/` holds lifecycle hooks, run state and the writer.
- `spec/thor/` covers runtime behavior and real subprocesses.
- `script/release.rb` uses modern Ruby only.

Run `bundle install`, then `bundle exec rake` for quality checks, specs and
installed-gem smoke tests. Compatibility jobs use `Gemfile.compat`.

Preserve Thor's dispatch, exceptions, exit status and caller-owned streams.
Keep records bounded and sanitize text. Do not add process-wide exit hooks,
signal handlers, terminal queries or worker aggregation.

Pre-1.0, no API-stability promise. Two interfaces: the Ruby API
(hook installation and preserved Thor behavior) and the emitted escape
sequences, which consumers parse. OSC 7501 frames must keep conforming.
Patch for fixes, minor for new behavior including added sequences;
removing or changing sequences is breaking.

Release with `script/release.rb prepare <version> <dir>`, build the gem,
then `publish <dir> <gem>`: the script handles the tag, the atomic main+tag
push, the RubyGems push and the GitHub release, then verifies the published
gem. If a release fails, inspect the logs and rerun the same version to
finish missing steps.

All authored Ruby files and methods require inline RBS without blanket untyped
annotations. Keep type tools in modern development bundles. Do not commit
gems, HTML, lockfiles, bundle state or generated signatures. Preserve LICENSE
verbatim. Agent plans and designs belong in GBrain, never Git.
