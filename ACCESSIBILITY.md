# Accessibility

Read command output without relying on terminal status indicators. Thor keeps
ordinary command output, prompts, and errors available as text.

## Plain text output

Disable status reporting for a Thor invocation:

```sh
THOR_OSC7501=off bundle exec thor deploy
```

`THOR_OSC7501=off` disables status records and terminal title updates.
Commands control their own text colors and output formats.

By default, Thor sends no status records to pipes, files, or terminals with
`TERM=dumb`. `THOR_OSC7501=force` overrides those defaults.

## Environments and limits

The gem requires MRI Ruby 2.1 or newer and Thor 0.19.4 or newer.
Terminal status requires an OSC 7501-capable terminal. The gem checks for a TTY
and honors `TERM=dumb` but does not detect OSC support.

Your terminal controls display and announcements. I have not tested the status
display with screen readers. Your screen reader may need additional settings.

## Report a barrier

Open an [issue](https://github.com/cosgroveb/thor-osc7501/issues) describing what
you tried, what prevented you from using it, and what would help. Include your
terminal, operating system, and assistive technology versions when relevant.
You do not need to disclose a disability or other medical information.
