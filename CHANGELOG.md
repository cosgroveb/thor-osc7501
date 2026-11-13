# Changelog

## 0.1.0 - 2026-11-13

- Initial release: generic OSC 7501 status for Thor commands and prompts,
  activated by requiring `thor/osc7501`
- One root record per outer run with nested-command restoration and
  concurrent-command counts
- Blocked attention records for `ask`, `yes?` and `no?` prompts with
  pending-prompt priority and no answer leakage
- `THOR_OSC7501=auto|off|force` output control following the Rake adapter
- Compatibility floor of MRI >= 2.1 and Thor >= 0.19.4, with packaged RBS signatures
