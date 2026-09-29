#!/usr/bin/env bash
# block-git-hook-bypass.sh — PreToolUse hook（Bash）：擋下繞過 git hook 的 commit 與 push。
#
# 為什麼是 hook，不是一句規矩
# --------------------------
# 「不准 --no-verify」以前只是散文：一則 memory、一條常駐規矩。2026-09-29 寫下那條規矩的
# 同一個 session，為了驗一條量測會不會紅，在 worktree 裡用 `-c core.hooksPath=/dev/null` 加
# `--no-verify` 提了一顆臨時 commit。那一顆沒推出去是運氣，不是機制——這條路存在，就會再被
# 走一次。使用者當天的原話：「不應該有 --no-verify，這應該要是硬限制」。
#
# 它守的後果三件同時成立（CLAUDE.md〈檢查類腳本的門檻〉）：繞過 hook 的 commit 推出去就
# 收不回來；看 diff 的人看不出它是怎麼進來的；而使用者指名要硬限制。
#
# 擋哪幾種
# --------
# - commit 帶 --no-verify 或 -n（含 -anm 這種短旗標串、以及 --no-verif 這種 git 會接受的縮寫）
# - push 帶 --no-verify（push 的 -n 是 dry-run，不擋）
# - `git -c core.hooksPath=…`、`--config-env=core.hooksPath=…` 接 commit／push／merge／rebase／am／cherry-pick／revert
# - commit 或 push 前面帶 GIT_CONFIG_* 或把 HOME／XDG_CONFIG_HOME 換掉（含 env、export）
# - `git config` 設定或刪除 core.hooksPath（讀取不擋）
# - merge 帶 --no-verify；`git -c alias.X=…` 的值裡藏著繞法；rebase -x／--exec 跑的命令
# - 單獨一行把 HOME／XDG_CONFIG_HOME／GIT_CONFIG_* 賦值之後再 commit 或 push（HOME 本來就是
#   export 的，單獨賦值就會傳給 git）
#
# 包一層也看得到：timeout／nice／env／time -p 這類前綴、( … )、{ …; }、function、if … then、
# bash -c／-lc '…'、bash <<< '…'、eval、反斜線續行、`$(which git)`／反引號／變數當命令名、
# 餵給殼的 heredoc（bash <<EOF、cat <<EOF | bash）、以及 echo '…' | bash。
#
# 擋不到什麼，明講
# ----------------
# - 只看得到 Claude 這個 Bash 工具送出的命令字串。包在另一支腳本檔裡再執行的，看不到；人
#   自己在終端機打的，也不經過這裡。git alias 裡藏的繞法也看不到。
# - 只在登記它的那個工作區生效（使用者 2026-09-29 裁：只登記框架 repo）。
#
# 命令字串解析不了（例如引號不成對）時不放水：退回用字面比對，看得到繞法就擋。
#
# 這一行是宣告：它講的是 git，不綁任何一家公司或這台機器，所以跟著 template 出去——
# settings.json 每次都會同步出去，hook 不出去的話那邊的設定會指向一個不存在的檔案。
# POLARIS-SCOPE: universal
#
# Input:  stdin JSON（tool_name、tool_input.command）
# Exit:   0 放行；2 擋下，理由寫在 stderr（Claude Code 會把它交回給模型）

set -uo pipefail

payload=$(cat)

if ! command -v python3 >/dev/null 2>&1; then
  # 沒有 python3 就退回字面比對：寧可多擋，不可安靜放行。
  if printf '%s' "$payload" | grep -qE '"tool_name" *: *"Bash"' &&
     printf '%s' "$payload" | grep -qE 'git' &&
     printf '%s' "$payload" | grep -qE -- '--no-verify|core\.hooksPath|GIT_CONFIG_|HOME='; then
    echo "已擋下：這個命令看起來在繞過 git hook（這台機器沒有 python3，只能做字面比對）。" >&2
    echo "不准繞過 git hook 提交或推送；hook 紅了就修好再提交，要驗量測就量工作區的改動，不要為此提 commit。來源：memory feedback-never-bypass-a-gate-in-a-company-repo。" >&2
    exit 2
  fi
  exit 0
fi

printf '%s' "$payload" | python3 -c '
import json, re, shlex, sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if data.get("tool_name") != "Bash":
    sys.exit(0)
cmd = (data.get("tool_input") or {}).get("command") or ""

HOOKED = {"commit", "push", "merge", "rebase", "am", "cherry-pick", "revert"}
# 帶 --no-verify 就繞過 hook 的子命令（push 的 -n 是 dry-run，merge 沒有 -n 這個縮寫）
NO_VERIFY_SUBS = {"push", "merge"}
ENV_BYPASS = re.compile(r"^(GIT_CONFIG\w*|HOME|XDG_CONFIG_HOME)$")
ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=")
GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
# commit 的短旗標裡，這幾個會把同一串後面的字元吃成值（-m 訊息、-u 模式……）
COMMIT_SHORT_TAKES_REST = set("mFcCtuS")
# 殼的關鍵字與包一層的命令：git 可能接在它們後面
SHELL_WORDS = {"(", ")", "{", "}", "!", "if", "then", "else", "elif", "fi", "do", "done", "while", "until", "time"}
WRAPPERS = {"env", "command", "exec", "sudo", "nohup", "nice", "ionice", "timeout", "stdbuf", "xargs", "caffeinate"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
SEPARATORS = set(";&|\n()")


def is_no_verify(tok):
    # git 接受長旗標的唯一前綴：--no-veri 起跳就只可能是 --no-verify（--no-ver 會撞 --no-verbose）
    return tok.startswith("--no-veri") and "--no-verify".startswith(tok.split("=", 1)[0])


def split_heredocs(text):
    """回傳（剝掉 heredoc 內文的命令、要當命令再判一次的內文）。

    heredoc 的內文是資料——裡面寫著 git commit --no-verify 的說明文字不擋。例外是餵給殼的
    heredoc（bash <<EOF），那一段就是命令。"""
    out, bodies, lines, i, quote = [], [], text.split("\n"), 0, None
    while i < len(lines):
        line = lines[i]
        out.append(line)
        i += 1
        ops, quote = heredoc_ops(line, quote)
        for start, word in ops:
            body = []
            while i < len(lines) and lines[i].strip() != word:
                body.append(lines[i])
                i += 1
            i += 1
            before = re.findall(r"[A-Za-z0-9_./-]+", line[:start])
            fed = before and before[-1].rsplit("/", 1)[-1] in SHELLS
            piped = re.search(r"\|\s*(\S*/)?(" + "|".join(SHELLS) + r")\b", line[start:])
            if fed or piped:
                bodies.append("\n".join(body))
    return "\n".join(out), bodies


def heredoc_ops(line, quote):
    """找出這一行裡真的是 heredoc 的 <<WORD：在引號裡、註解裡、或 <<< 的都不算。
    quote 是上一行結束時還沒關上的引號，跨行的字串裡也不算。"""
    ops, j, n = [], 0, len(line)
    while j < n:
        c = line[j]
        if quote:
            if c == "\\" and quote == "\x22":
                j += 2
                continue
            if c == quote:
                quote = None
            j += 1
            continue
        if c == "\\":
            j += 2
            continue
        if c in "\x27\"":
            quote = c
        elif c == "#" and (j == 0 or line[j - 1] in " \t;&|("):
            break
        elif line.startswith("<<<", j):
            j += 3
            continue
        elif line.startswith("<<", j):
            m = re.match(r"<<-?\s*([\x27\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line[j:])
            if m:
                ops.append((j, m.group(2)))
                j += m.end()
                continue
        j += 1
    return ops, quote


def tokenize(text):
    text = re.sub(r"\\\n", "", text)  # 反斜線續行：bash 會把兩行接成一個命令
    lex = shlex.shlex(text, posix=True, punctuation_chars=";&|\n()")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    return list(lex)


def segments(tokens):
    """逐段交出（前一個分隔符號, 這一段的 token）。"""
    seg, sep = [], ""
    for t in tokens:
        if t and set(t) <= SEPARATORS:
            if seg:
                yield sep, seg
            seg, sep = [], t
        else:
            # ANSI-C 引號 $「--no-verify」被 shlex 讀成 $--no-verify；bash 讀成 --no-verify
            seg.append(t[1:] if t.startswith("$-") else t)
    if seg:
        yield sep, seg


def judge_config(rest):
    """git config 讀 core.hooksPath 放行，設定或刪除才擋。"""
    pos = [a for a in rest if not a.startswith("-")]
    opts = [a for a in rest if a.startswith("-")]
    keys = [k for k, a in enumerate(pos) if a.lower() == "core.hookspath"]
    if not keys:
        return None
    if pos and pos[0] in ("get", "list"):
        return None
    if pos and pos[0] in ("set", "unset", "unset-all", "replace-all", "add"):
        return "git config " + pos[0] + " core.hooksPath"
    if any(o.startswith(("--unset", "--add", "--replace-all")) for o in opts):
        return "git config 刪改 core.hooksPath"
    if keys[0] + 1 < len(pos):
        return "git config 設定 core.hooksPath"
    return None


def judge_git(args, env_names):
    """args 是 git 之後的 token。回傳命中的繞法說明，沒命中回 None。"""
    i, hookspath = 0, False
    while i < len(args):
        a = args[i]
        low = a.lower()
        if a in GIT_OPTS_WITH_VALUE:
            val = args[i + 1] if i + 1 < len(args) else ""
            if val.lower().startswith("core.hookspath"):
                hookspath = True
            if a == "-c" and val.lower().startswith("alias.") and "=" in val:
                hit = judge_alias(val.split("=", 1)[1])
                if hit:
                    return "git -c " + val.split("=", 1)[0] + " 藏著 " + hit
            i += 2
            continue
        if a.startswith("-"):
            if low.startswith("-ccore.hookspath") or low.startswith("--config-env=core.hookspath"):
                hookspath = True
            i += 1
            continue
        break
    if i >= len(args):
        return None
    sub, rest = args[i], args[i + 1:]
    if sub in HOOKED and hookspath:
        return "git 以 core.hooksPath 覆寫接 " + sub
    if sub in HOOKED and env_names:
        return "在 " + sub + " 前面換掉 " + "、".join(sorted(env_names))
    if sub == "commit":
        j = 0
        while j < len(rest):
            a = rest[j]
            if a == "--":
                break
            if is_no_verify(a):
                return "git commit " + a
            if re.match(r"^-[A-Za-z]+$", a):
                for k, ch in enumerate(a[1:]):
                    if ch == "n":
                        return "git commit " + a + "（-n 就是 --no-verify）"
                    if ch in COMMIT_SHORT_TAKES_REST:
                        if k == len(a) - 2 and ch in "mFcCt":
                            j += 1  # 值在下一個 token
                        break
            elif a in ("--message", "--file", "--reuse-message", "--reedit-message", "--template", "--author", "--date"):
                j += 1
            j += 1
    if sub in NO_VERIFY_SUBS and any(is_no_verify(a) for a in rest):
        return "git " + sub + " --no-verify"
    if sub == "rebase":
        for n, a in enumerate(rest):
            val = None
            if a in ("-x", "--exec") and n + 1 < len(rest):
                val = rest[n + 1]
            elif a.startswith("--exec="):
                val = a.split("=", 1)[1]
            elif a.startswith("-x") and len(a) > 2:
                val = a[2:]
            hit = val and judge(val)
            if hit:
                return "git rebase --exec 跑的命令：" + hit
    if sub == "config":
        return judge_config(rest)
    return None


def judge_alias(value):
    """alias 的值：! 開頭是殼命令，否則是 git 的子命令與參數。"""
    if value.startswith("!"):
        return judge(value[1:])
    return judge("git " + value)


def git_after(seg, start):
    """命令名是 $(which git)、反引號或變數時，往後找到 git 那一個 token 的下一格。"""
    for n in range(start, len(seg)):
        if seg[n].strip("`)").rsplit("/", 1)[-1] == "git":
            return n + 1
    return None


def judge_segment(seg, exported, prev_sep="", prev_seg=()):
    env_names, k = set(), 0
    if seg and seg[0] in ("export", "declare", "typeset", "readonly", "local"):
        for a in seg[1:]:
            m = ASSIGN.match(a)
            if m and ENV_BYPASS.match(m.group(1)):
                exported.add(m.group(1))
        return None
    if seg and all(ASSIGN.match(a) for a in seg):
        # 單獨一行的賦值：HOME 本來就 export，改了就傳給之後每一個命令；GIT_CONFIG_* 在
        # set -a 之下也一樣。寧可當成已 export。
        for a in seg:
            m = ASSIGN.match(a)
            if ENV_BYPASS.match(m.group(1)):
                exported.add(m.group(1))
        return None
    while k < len(seg):
        if seg[k] in SHELL_WORDS:
            k += 1
        elif seg[k] == "function" and k + 1 < len(seg):
            k += 2  # function 名字
        elif seg[k].startswith("-") and k > 0 and seg[k - 1] in ("time", "-p"):
            k += 1  # time -p
        else:
            break
    while k < len(seg):
        m = ASSIGN.match(seg[k])
        if m:
            if ENV_BYPASS.match(m.group(1)):
                env_names.add(m.group(1))
            k += 1
        else:
            break
    if k >= len(seg):
        return None
    head = seg[k].rsplit("/", 1)[-1]
    if head == "eval":
        return judge(" ".join(seg[k + 1:]))
    if head in SHELLS:
        rest = seg[k + 1:]
        for n, a in enumerate(rest):
            if re.match(r"^-[a-z]*c[a-z]*$", a) and n + 1 < len(rest):
                return judge(rest[n + 1])  # bash -c／-lc／-ec 接的那一段
            if a == "<<<" and n + 1 < len(rest):
                return judge(rest[n + 1])
        if prev_sep == "|" and all(a.startswith("-") for a in rest) and prev_seg:
            # echo 一段字 | bash：前一段印出來的就是要跑的命令
            return judge(" ".join(prev_seg[1:]))
        return None
    if seg[k][:1] in ("$", "`"):
        n = git_after(seg, k)
        return judge_git(seg[n if n is not None else k + 1:], env_names | exported)
    if head in HOOKED and prev_seg and prev_seg[-1].strip("`").rsplit("/", 1)[-1] == "git":
        return judge_git(seg[k:], env_names | exported)  # $(which git) commit
    if head in WRAPPERS:
        # 包一層的命令：往後找 git；中間的 NAME=VALUE 照樣算換環境
        for n in range(k + 1, len(seg)):
            m = ASSIGN.match(seg[n])
            if m and ENV_BYPASS.match(m.group(1)):
                env_names.add(m.group(1))
            if seg[n].rsplit("/", 1)[-1] == "git":
                return judge_git(seg[n + 1:], env_names | exported)
        return None
    if head == "git":
        return judge_git(seg[k + 1:], env_names | exported)
    return None


def judge(text):
    exported = set()
    commands, bodies = split_heredocs(text)
    prev = ()
    for sep, seg in segments(tokenize(commands)):
        hit = judge_segment(seg, exported, sep, prev)
        if hit:
            return hit
        prev = seg
    for body in bodies:
        hit = judge(body)
        if hit:
            return hit
    return None


FALLBACK = re.compile(
    r"(^|\s)(--no-veri\w*|-[A-Za-z]*n[A-Za-z]*\b|-c\s*core\.hooksPath|--config-env\S*core\.hooksPath"
    r"|GIT_CONFIG_\w*=|HOME=|core\.hooksPath\s+\S)", re.IGNORECASE)

try:
    hit = judge(cmd)
except ValueError:
    # 解析不了（引號不成對之類）：退回字面比對，看得到繞法就擋。寧可多擋，不可安靜放行。
    hit = None
    if re.search(r"\bgit\b", cmd) and re.search(r"\b(commit|push|config|merge|rebase|am|cherry-pick|revert)\b", cmd) \
            and FALLBACK.search(cmd):
        hit = "命令解析不了，但字面上看得到繞過 hook 的寫法"

if not hit:
    sys.exit(0)

sys.stderr.write(
    "已擋下：" + hit + "。\n"
    "這個工作區不准繞過 git hook 提交或推送（使用者 2026-09-29 拍板：這應該要是硬限制）。"
    "繞過 hook 的 commit 一推出去就收不回來，而看 diff 的人看不出它是怎麼進來的。\n"
    "正確做法：hook 紅了就把紅的修好再提交；要驗一條量測會不會紅，直接量工作區的改動，"
    "不要為此提一顆 commit。\n"
    "來源：memory feedback-never-bypass-a-gate-in-a-company-repo。\n"
)
sys.exit(2)
'
