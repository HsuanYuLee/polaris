---
name: framework-release
description: |
  判定通過之後把東西送出去的那一段：把分支併進 main、壓版號、視目的地同步到 template repo、把本機接回釋出後的狀態。它不判斷該不該出貨——那是 verify-ac 寫在交付紀錄裡的事。

  某張單已經judged PASS、交付紀錄寫好了，要真的出貨的時候。例如「出貨吧」
  「釋出」「壓版本」「同步到 template」，或剛從 verify-ac 交出來。

  也用於：只想先看它打算做什麼（預設就是預覽，不加 --execute 不會動任何東西）。

  不用於：還沒有交付紀錄（先走 verify-ac）、判定還沒過（那是 verify-ac 的事）。
metadata:
  requires:
    - skill: verify-ac
      why: 這支讀的那份交付紀錄是它寫的；沒有 delivery.json，第一道閘就 die，整段釋出跑不起來
    - skill: driving-work-to-done
      why: gate-spine-delivery.sh 直接解出它的 spine-loop-state.sh 來跑（判落腳處），不是只在訊息裡提到它
scope: framework
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

## 被打斷了：先問它走到哪

```bash
bash .claude/skills/framework-release/scripts/spine-release.sh --issue {issue} --status
```

**逐項問每一個系統，然後直接重跑 `--execute` 就好。** 每一步在做之前都會先問那個真的擁有
那件事的系統——`git ls-remote` 問 tag、`gh release view` 問 release、`merge-base` 問促進、
template checkout 自己問同步——所以做過的會被跳過，沒做的會被補上。

**沒有進度檔，這是刻意的。** 一份「做到第幾步」的本機紀錄是同一件事的第二個答案，而第一個
答案在 origin、在 GitHub、在 template checkout 上。兩份會漂，而漂掉的那一刻正好是有人被
打斷、最需要一句真話的時候。

問不到的那一項會說它問不到（例如 `gh` 不在、`origin/main` 的物件本機沒有），不會省略、
也不會猜一個——一個安靜的第三態，下一次就會被當成查過了。

## 尾段做哪幾件事

1. **重驗** —— fence 與交付紀錄都要還成立。任一項不成立就停，這時候還沒有任何東西被送出去。
2. **壓版號** —— 讀 changeset 決定 patch / minor / major。**`.changeset/` 就是版號唯一的
   宣告源**，交付紀錄裡沒有這件事也不該有：那份紀錄由可攜層寫，而版號是這條尾段自己的
   模型。有 changeset 卻沒壓動的話這是矛盾，不是可以印一行 note 略過的事。
3. **促進 main** —— 找到這條 branch **已經開好**的 PR，過閘之後 fast-forward。不是直接推 main。

   **這支不開 PR。** 它 `gh pr list --state open`；開 PR 是 SWE 的 definition of done，屬
   `swe-knowledge`——PR 開出來就是實作完成，而這支是完成**之後**的事。

   **但「沒有 open PR」有兩種原因，而它們要的下一步相反**：還沒開，或者已經併進去了。
   所以找不到的時候它再問一次 git「這條分支在不在 `origin/main` 裡」——在，就說出促進
   上一趟已經做完並跳過這一步；不在，才 die（`POLARIS_SPINE_RELEASE_NO_PR`）。少了這一問
   的那一版，尾段被打斷之後重跑一定走到 die，而它建議的修法是去開一個空的 PR。

   **壓完版號就要促進到 main，不停在中間。** 一個壓了版號卻沒進 main 的 commit，是一個宣稱
   已經發生、但任何人 clone 下來都看不到的版本。這兩步之間沒有停點。
4. **同步 template** —— 只有 `destination: template` 的單才做。`workspace` 的到第 3 步為止。
5. **打 tag、建 release** —— **兩件事，各問各的系統。** tag 問 `git ls-remote --tags origin`，
   release 問 `gh release view`。用一個判斷答兩件事的那一版，在「tag 推出去了、release 還
   沒建」那個中斷點重跑會印「already on origin」然後回報出貨完成，而那個 release 從來沒有
   存在過。問不到 release 在不在的時候**停**，不當成已經有了。
6. **接回本機** —— main 快轉、git hook 重裝、已併的分支刪掉。

`destination` 是人在閘一宣告的，寫在 `{issue}/index.md` 的 frontmatter。這裡只讀不改。

## 它自己帶的閘

釋出是不可逆的那一刻，所以擋在這裡的東西擋的都是「送出去就收不回來」：

| 閘 | 擋什麼 |
|---|---|
| `gate-spine-delivery.sh` | 交付紀錄不存在、或釘的是另一個 commit |
| `gate-template-leaks.sh` | live company slug 進公開的 template repo |
| `gate-runtime-instruction-manifest.sh` | 生成的常駐指令過期——之後每個 session 都會靜默讀到錯的那份 |
| `gate-no-tracked-specs.sh` | 個人的規劃內容混進這個 repo |
| `gate-skill-script-references.sh` | skill 腳本從自己的位置算起指名一個不存在的東西——搬家留下的洞，執行期才炸。被存在性檢查包住的算候選，整組落空才紅 |
| `gate-prose-matches-behaviour.sh` | SKILL.md 指名的檔案／子命令／旗標對不上實際行為——同一個洞的散文那一面 |
| `gate-skill-knowledge-locality.sh` | 一支 skill 靠工作區底下沒有版控的東西才跑得動——在寫下它的人的機器上全綠，別人 clone 下來就是壞的 |
| `gate-source-destination.sh` | 宣告了 `destination: workspace`，卻有檔案落在會被同步出去的位置 |
| `gate-copy-sets.sh` | 同一個名字在多支 skill 底下的那幾份漂開了、或多出一份說不出自己為什麼在那裡——副本是刻意的，沒有東西維持它們一致才是病 |

上面這些掃全樹的閘合計 1.3 秒，所以它們掛在 **commit** 上，不是 push——一個過不了閘的
commit 已經在歷史裡了，那時候修要改寫歷史。

## 本機這一層擋得住什麼、擋不住什麼

**它不是安全網，是一層會被自願跑的檢查。** 這一句要先講：一份把自己說成安全網的說明，會讓
下一個人不去問「那誰在擋」。

兩個 hook 真正被執行的內容住在 `githooks/`，是版控裡的兩個檔案——改它們會出現在 diff 裡，
一個新 clone 接上一次就拿到當前的版本：

| hook | 跑什麼 | 為什麼是這個範圍 |
|---|---|---|
| `githooks/pre-commit` | 上面那幾道掃全樹的閘 ＋ `run-selftests.sh --staged` | 只跑這次 staged 動到的那幾支 skill。過不了閘的 commit 從來不存在 |
| `githooks/pre-push` | 同一批閘 ＋ `run-selftests.sh --since-base` | 這條分支相對於預設分支動過的**所有**檔案所屬的 skill。不是最後一次 commit 動到的那些（分支前面幾個 commit 動過的會整個漏掉），也不是全套——全套 87.7 秒，掛在每次推送上會被關掉，而一個被關掉的檢查比沒有檢查糟 |

`--since-base` 算不出範圍時（`origin/HEAD` 沒設、shallow clone、跟預設分支沒有共同祖先）
會**說出原因並退回跑全套**，不會安靜地一支都不跑。

接上的方式是把 `core.hooksPath` 指向那個目錄，不是把內容複製進 `.git/hooks/`：

```bash
bash .claude/skills/framework-release/scripts/install-git-hooks.sh            # 接上
bash .claude/skills/framework-release/scripts/install-git-hooks.sh --status   # 看狀態
bash .claude/skills/framework-release/scripts/install-git-hooks.sh --remove   # 拆掉
```

**代價要說出來**：`core.hooksPath` 一設，`.git/hooks/` 底下所有東西都失效，包含別人手寫的。
所以接上之前它會掃那個目錄，有不是這套裝的（`[polaris-git-hooks]` 標記以外的）就指名並停
下來——用一個靜默的停用換一個宣稱的保障，比不接還糟。

<!-- POLARIS-GIT-HOOKS: .claude/skills/framework-release/githooks | bash .claude/skills/framework-release/scripts/install-git-hooks.sh -->

上面那一行是機器讀的：`swe-knowledge` 的開工條件掃它，沒接上就不開輪次。它不認得這個目錄
叫什麼、也不認得這支安裝器——換一套 hook 只要換那一行。

### 它擋不住的那幾條

| 繞過的方式 | 為什麼擋不住 |
|---|---|
| `git commit --no-verify`、`git push --no-verify` | 一個字。hook 的存在本來就假設呼叫者願意跑它 |
| 直接推預設分支 | 沒有 branch protection（要 repo admin），而本機 hook 不區分推去哪 |
| 遠端沒有任何強制 | github.com 沒有 server-side hook，`pre-receive` 只有 GitHub Enterprise Server 有。這個 repo 的 `.github/workflows/ci.yml` 從來沒有跑過一次（`total_count: 0`），要打開它需要 admin |
| 從一個還沒有 `githooks/` 的分支開 worktree | `core.hooksPath` 存的是相對路徑，那個工作樹裡的目錄不存在，git 安靜地什麼都不跑 |
| 事後把 hook 檔案的執行位元拿掉 | git 安靜地跳過它。安裝器與開工條件都會擋，但那是它們跑的那一刻的事 |

**真正在擋的是這條尾段。** 促進到 main 之前它重跑全套閘與全套 selftest——走脊椎出去的東西
是被檢查過的，暴露面只有上面那幾條繞過脊椎的路。這一層不假裝能關掉它們，只負責讓「有接上、
有跑、跑得夠」這三件成立。

## 從哪裡跑

**從主 checkout 跑，不要從 linked worktree。** 兩個理由疊在一起：交付紀錄住在 `issues/`，
而那是版控在別處的目錄，worktree 裡不存在；而且尾段的閘要看只屬於這台機器的目錄（公司
的 repo、快取），worktree 裡也沒有——它們會對一整批忽略規則回「現在沒有排除到任何東西」
而擋下 push。施工可以在 worktree 裡，尾段不行。

**壓完版要再量一次。** 壓版會產生一個新的 commit，而交付紀錄要求每條斷言的證據綁**交付
的那個 head**。這一步的 re-pin 只重寫紀錄、不重跑量測，所以第一次一定會被自己的檢查擋
下來。撞到的時候順序是：在新 head 上重跑量測 → 重寫交付紀錄 → 再跑一次 `--execute`
（這時已經沒有待消化的 changeset，不會再壓一次版）。

## 壓完版之後那條鏈

尾段做完的那六件事之外，這個框架自己還有一段迭代程序——壓版之後要跑的 docs-lint、待辦
掃描、驗證過的樣式怎麼升格。它寫在 `references/framework-iteration-procedures.md`，
**按需載入**，不是每次釋出都要讀。

那份程序裡指名的 docs-lint 就在這支 skill 底下：

```bash
python3 .claude/skills/framework-release/scripts/readme-lint.py            # 只檢查
python3 .claude/skills/framework-release/scripts/readme-lint.py --fix      # 順手改掉數字
python3 .claude/skills/framework-release/scripts/readme-lint.py --verbose  # 全部細節
```

它比對的是「文件裡講的 skill」與「真的存在的 SKILL.md」：數量、指向不存在的 skill、
存在卻沒有人提過的 skill、觸發詞表、流程圖節點。**它掃的是會跟著 template repo 出去的
那幾份文件**（README、`docs/`），所以它守的是別人 clone 下來第一眼讀到的東西。

這兩樣 2026-08-13 從 `standup/` 搬過來（DP-536）——它們講的是這個框架怎麼迭代，不是
怎麼產出每日站會報告。

## 卡住的時候

**沒有交付紀錄** —— 回 `verify-ac` 跑它的交付步驟。這支不會替你寫一份。

**紀錄釘的 commit 不是現在的 HEAD** —— 判定之後又有新 commit。要嘛把那些 commit 也送審，
要嘛回到被判定的那個狀態。不要重寫紀錄去遷就 HEAD。

**但有一種例外，而它自己證明得了**：HEAD 就是上一趟被打斷前壓的那個版號 commit——直接坐在
被判定的 head 上，而且只碰了 `VERSION`／`CHANGELOG.md`／`package.json`／`.changeset`。
這一種尾段自己會重釘並往下走。兩個條件任一不成立就照舊拒絕，並說出是哪一項不成立。

**fence 對不上** —— 斷言在判定之後被動過。這比版本號錯嚴重：對著一份沒人簽過的成功定義
出貨，比不出貨糟。回 `refinement` 重簽，然後整條重走。

<!-- PROSE-EXTERNAL-PATHS: docs-manager/ — 動手對象：那是 specs 站台自己的 repo，這支 skill 往它寫東西、讀它的結構，不是我們抄一份放著的知識 -->
