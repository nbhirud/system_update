#!/usr/bin/env python3
"""helper_starship_patch.py - patch the built-in Starship "catppuccin-powerline" preset.

WHAT IT DOES
  Reads the preset produced by `starship preset catppuccin-powerline -o <file>` and writes a patched copy:
    * palette           -> the requested palette (default flavor of the preset is catppuccin_mocha)
    * command_timeout / scan_timeout -> machine dependent values
    * format            -> rebuilt: OS/user -> directory are always shown; git, languages, cloud/dev tools
                           and the last command's duration are OPTIONAL "tags" wrapped in ( ... ), which
                           Starship omits completely when every module inside is empty
    * [username]        -> shown only for root / SSH (no always-on username)
    * [hostname]        -> shown only in SSH sessions (so local terminal output stays clean)
    * [cmd_duration]    -> shown after every command (min_time = 0) with milliseconds, no notifications
    * [aws]             -> built-in module disabled; AWS appears only when AWS_PROFILE / AWS_REGION are set
    * [terraform]       -> styled to match the cloud/dev tag
  The glyphs come from the preset's own powerline characters (U+E0B6 / E0B0 / E0B2); no glyph is typed
  by hand in this file.

USAGE
  helper_starship_patch.py <preset.toml> <output.toml> <palette> [command_timeout_ms] [scan_timeout_ms]

EXIT CODES
  0 success; non-zero when a marker expected in the preset is missing (the preset changed upstream).
  The caller then falls back to the unmodified preset.
"""
import re
import sys

CAP_L, ARROW, ARROW_L = "\ue0b6", "\ue0b0", "\ue0b2"


def sub_once(pattern, repl, text, flags=0):
    new, n = re.subn(pattern, lambda m: repl, text, count=1, flags=flags)
    if n != 1:
        raise SystemExit("patch marker not found in preset: " + pattern[:50])
    return new


def replace_section(text, name, body):
    pat = r"^\[" + re.escape(name) + r"\]\n.*?(?=^\[|\Z)"
    return sub_once(pat, body.strip("\n") + "\n\n", text, re.S | re.M)


def pill(color, body):
    # ( <left arrow> modules <right arrow> ): omitted entirely when all modules inside are empty.
    return f"( [{ARROW_L}](fg:{color}){body}[{ARROW}](fg:{color}))"


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    src, dst, palette = sys.argv[1], sys.argv[2], sys.argv[3]
    cmd_timeout = sys.argv[4] if len(sys.argv) > 4 else "500"
    scan_timeout = sys.argv[5] if len(sys.argv) > 5 else "30"
    t = open(src, encoding="utf8").read()

    fmt = (
        f"[{CAP_L}](fg:red)$os$username$hostname[{ARROW}](bg:peach fg:red)$directory[{ARROW}](fg:peach)"
        + pill("yellow", "$git_branch$git_status")
        + pill("green", "$c$rust$golang$nodejs$bun$php$java$kotlin$haskell$python$conda")
        + pill("sapphire", "$docker_context$terraform${env_var.AWS_PROFILE}${env_var.AWS_REGION}")
        + pill("lavender", "$cmd_duration")
        + "$line_break $character"
    )
    t = sub_once(
        r'format = """.*?"""',
        f"command_timeout = {cmd_timeout}\nscan_timeout = {scan_timeout}\n\n" + 'format = """\n' + fmt + '"""',
        t, re.S,
    )
    t = sub_once(r"^palette = '[^']*'", f"palette = '{palette}'", t, re.M)

    t = replace_section(t, "username", """[username]
show_always = false
style_user = "bg:red fg:crust"
style_root = "bg:red fg:crust"
format = '[ $user ]($style)'""")
    t = replace_section(t, "cmd_duration", """[cmd_duration]
min_time = 0
show_milliseconds = true
format = '[[ took $duration ](fg:crust bg:lavender)]($style)'
style = 'bg:lavender'
show_notifications = false""")

    t = t.rstrip("\n") + "\n" + """
[hostname]
ssh_only = true
style = "bg:red fg:crust"
format = '[@$hostname ]($style)'

[aws]
disabled = true

[env_var.AWS_PROFILE]
variable = "AWS_PROFILE"
style = "bg:sapphire"
format = '[[ aws $env_value ](fg:crust bg:sapphire)]($style)'

[env_var.AWS_REGION]
variable = "AWS_REGION"
style = "bg:sapphire"
format = '[[ $env_value ](fg:crust bg:sapphire)]($style)'

[terraform]
symbol = "tf"
style = "bg:sapphire"
format = '[[ $symbol( $workspace) ](fg:crust bg:sapphire)]($style)'
"""
    open(dst, "w", encoding="utf8").write(t)


if __name__ == "__main__":
    main()
