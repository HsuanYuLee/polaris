---
name: framework-release
description: 判定通過之後把東西送出去的那一段：把分支併進 main、壓版號、視目的地同步到 template repo、把本機接回釋出後的狀態。它不判斷該不該出貨——那是 verify-ac 寫在交付紀錄裡的事。
when_to_use: |
  某張單已經judged PASS、交付紀錄寫好了，要真的出貨的時候。例如「出貨吧」
  「釋出」「壓版本」「同步到 template」，或剛從 verify-ac 交出來。

  也用於：只想先看它打算做什麼（預設就是預覽，不加 --execute 不會動任何東西）。

  不用於：還沒有交付紀錄（先走 verify-ac）、判定還沒過（那是 verify-ac 的事）。
---

# framework-release — 釋出尾段

`verify-ac` 判 PASS 之後就結束了。它留下的是一份交付紀錄，不是一句「可以出貨了」。這支
skill 讀那份紀錄，把它變成真的發生的事。

**這裡不做判斷。** 該不該出貨、出什麼、算不算達成，全都在交付紀錄裡由 `verify-ac` 決定。
這支只負責執行，而且執行之前會把那份紀錄再驗一次——紀錄釘的 commit 跟現在的 HEAD 對不上
就停，斷言被動過也停。

## 先看它打算做什麼

```bash
bash .claude/skills/framework-release/scripts/spine-release.sh --issue {issue}
```

**預設是預覽，不會動任何東西。** 它會印出目的地、判定人、紀錄釘的 commit、現在的 HEAD、
以及接下來每一步打算做什麼。看過了再加 `--execute`。

```bash
bash .claude/skills/framework-release/scripts/spine-release.sh --issue {issue} --execute
```

## 尾段做哪幾件事

1. **重驗** —— fence 與交付紀錄都要還成立。任一項不成立就停，這時候還沒有任何東西被送出去。
2. **壓版號** —— 讀 changeset 決定 patch / minor / major。**沒有 changeset 就是沒有版本變更**，
   而交付紀錄裡宣告過 `version_bump` 的話這是矛盾，不是可以印一行 note 略過的事。
3. **促進 main** —— 開一個分支 → main 的 PR，過閘之後 fast-forward。不是直接推 main。
4. **同步 template** —— 只有 `destination: template` 的單才做。`workspace` 的到第 3 步為止。
5. **接回本機** —— main 快轉、git hook 重裝、已併的分支刪掉。

`destination` 是人在閘一宣告的，寫在 `{issue}/index.md` 的 frontmatter。這裡只讀不改。

## 它自己帶的閘

釋出是不可逆的那一刻，所以擋在這裡的東西擋的都是「送出去就收不回來」：

| 閘 | 擋什麼 |
|---|---|
| `gate-spine-delivery.sh` | 交付紀錄不存在、或釘的是另一個 commit |
| `gate-template-leaks.sh` | live company slug 進公開的 template repo |
| `gate-runtime-instruction-manifest.sh` | 生成的常駐指令過期——之後每個 session 都會靜默讀到錯的那份 |
| `gate-no-tracked-specs.sh` | 個人的規劃內容混進這個 repo |
| `gate-skill-script-references.sh` | skill 腳本指向不存在的同目錄檔案——搬家留下的洞，執行期才炸 |

前兩道也掛在 git 的 pre-push 上，由 `install-git-hooks.sh` 裝：

```bash
bash .claude/skills/framework-release/scripts/install-git-hooks.sh            # 裝
bash .claude/skills/framework-release/scripts/install-git-hooks.sh --status   # 看狀態
bash .claude/skills/framework-release/scripts/install-git-hooks.sh --remove   # 移除
```

它只會動自己裝的那些（檔案裡有 `[polaris-git-hooks]` 標記），別人手寫的 hook 不碰。

## 卡住的時候

**沒有交付紀錄** —— 回 `verify-ac` 跑它的交付步驟。這支不會替你寫一份。

**紀錄釘的 commit 不是現在的 HEAD** —— 判定之後又有新 commit。要嘛把那些 commit 也送審，
要嘛回到被判定的那個狀態。不要重寫紀錄去遷就 HEAD。

**fence 對不上** —— 斷言在判定之後被動過。這比版本號錯嚴重：對著一份沒人簽過的成功定義
出貨，比不出貨糟。回 `refinement` 重簽，然後整條重走。
