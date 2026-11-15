# thor-osc7501

Add OSC 7501 terminal status to ordinary Thor commands.

```ruby
# Gemfile
gem 'thor-osc7501', require: false
```

```ruby
# Thorfile
require 'thor/osc7501'
```

Run `bundle exec thor deploy`. A supporting terminal receives the run as its
root record with the current command and outcome. Each new run replaces it,
and ordinary command output, input, return values and exits continue
unchanged. A Ruby executable can require the same entrypoint before its CLI
class starts. `Klass.start` works the same way. Installing the gem alone
does not activate it.

## What is reported

One root record per outer run, `app=thor`, no identity and no percentage.
Reporting starts when the first command executes. Sequential nesting shows
the executing leaf command and restores its caller on return. Overlapping
commands show `N active commands`. Framework `help`, `list` and `version`
operations never count as work, while user commands with those names report
normally. Skipped invocations produce no records.

During `ask`, `yes?` or `no?`, the run reports `blocked` attention with the
prompt text (`kind=question`). Pending prompts take priority over working
commands. With several prompts pending, the most recently entered one shows
and the previous one resumes when it resolves. Entered answers are never
reported. After input returns, the current working status resumes.

Normal outer completion reports `done`. An escaping exception or
unsuccessful `SystemExit` reports `error`, and `Interrupt` or successful
`SystemExit` reports `idle`, preserving Thor's behavior. Errors handled
inside an enclosing command body do not finalize the run. Command return
values never imply success or failure.

## Output controls

| Setting | Behavior |
| --- | --- |
| `THOR_OSC7501=auto` | Default. Report to stdout only when it is a TTY and `TERM` is not `dumb`. |
| `THOR_OSC7501=force` | Report to stdout even when redirected. |
| `THOR_OSC7501=off` | Disable Thor reporting. |
| any other value | Raise `ArgumentError`. |

Reporting also sets the terminal title. While one command runs, the title is
`thor › <command>`. While several commands run in parallel, it is
`thor › <n> active commands`. The title returns to `thor` after the last
command, on completion, and on error or stop.

Reporting IO failures disable reporting without replacing the command's own
exception or result. Messages are sanitized to a single plain-text line and
capped at 2048 decoded UTF-8 bytes. Window titles are sanitized the same way
and capped at 512 bytes including the `thor › ` prefix. The ordinary terminal
prompt is unchanged.

## Boundaries

Observation covers Thor dispatch: normal CLI loading, direct `Klass.start`
and nested `invoke`, plus `Thor::Group` sequences through the same path.
Direct Ruby method calls that bypass Thor dispatch are outside scope.
Prompt coverage extends to `Thor::Shell::Basic`, `Color` and subclasses that
retain normal prompt behavior, including shells created before activation. A
custom shell overriding `ask` directly, or direct stdin reads, are outside
guaranteed coverage.

The concurrency guarantee covers overlapping invocations belonging to one
outer run. Unrelated simultaneous top-level starts, detached work outliving
the command, fork coordination and asynchronous frameworks are outside
first-release guarantees. Synchronous subprocesses keep the run working. We
do not inspect their output or auto-enable companion reporters, and an
independently enabled root reporter in a child can overwrite the shared root
record.

## Compatibility and development

MRI >= 2.1 and Thor >= 0.19.4, with no speculative upper bound. Development
requires a modern Ruby only for tooling:

```sh
bundle install
bundle exec rake
```

The default task checks inline RBS with Steep, runs the specs and exercises
the packaged gem in an isolated environment. `bundle exec rspec` runs the
specs alone. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development
workflow and [CHANGELOG.md](CHANGELOG.md) for changes.
