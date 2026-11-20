# Contributing

Follow the [code of conduct](CODE_OF_CONDUCT.md). Report vulnerabilities through
the private channel in [SECURITY.md](SECURITY.md).

AI-assisted contributions are welcome. Before requesting review, understand
the changes, run relevant checks, and verify claims in code, documentation,
and reports. State what you tested and what remains uncertain. Be prepared
to explain your choices and address feedback. When using an agent to help
answer a reviewer, check the answer and send only what is relevant.

Use MRI Ruby 3.4 or newer for development tooling. Install actionlint 1.7.12 on
your PATH, then run all checks:

```sh
bundle install
bundle exec rake
```

The default task runs RuboCop with rubocop-rspec, bundler-audit, actionlint,
inline RBS checks with Steep, the specs and installed-gem smoke tests. Run
`bundle exec rake lint`, `audit`, `workflows`, `types`, `spec`, `package` or
`smoke` for individual checks. RuboCop applies default style rules to release
tooling and build configuration, and correctness cops to runtime code, specs
and smoke tests. Dependency auditing uses the ignored lockfile from
`bundle install`.

`rake types` validates that every authored file opts into inline RBS, every
method carries a `#:` annotation, and Steep accepts the runtime and tooling
implementations in `lib/` and `script/` against the generated signatures.
Keep project types inline. `untyped` is accepted at the Thor framework
boundary but not as a substitute for known types. `sig/dependencies.rbs`
fills gaps in dependency signatures, including the `CommandHook` module
self type that rbs-inline cannot emit. Generated signatures live only in
ignored `tmp/` during development and inside the built gem under `sig/`,
never in the source tree.

Keep the runtime dependency limited to `thor`. Cover command, nesting and
prompt behavior with real Thor subprocesses: fixtures in `spec/support` run
isolated processes with bounded timeouts and reap every child. PTY fixtures
synchronize on observed state, not sleeps. Compatibility runs use
`Gemfile.compat` with pinned `THOR_VERSION` and `RSPEC_MINOR` on the oldest
supported Rubies. Do not load modern development tooling into Ruby 2.1
runtime checks.

Specs run in random order and report their seed. Reproduce an ordering
failure with `bundle exec rspec --seed <seed>` and narrow it with
`bundle exec rspec --seed <seed> --bisect`.
