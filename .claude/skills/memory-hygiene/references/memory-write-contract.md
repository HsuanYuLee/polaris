---
title: "Memory Write Contract"
description: "寫一份 memory 的時候要遵守的規矩：檔案放哪、索引寫哪、Hot 的軟上限、以及哪幾個 frontmatter 欄位是給分層用的。"
---

# 寫一份 memory 的時候
<!-- PROSE-EXTERNAL-PATHS: MEMORY.md — 使用者自己的 memory 目錄，不在這個 repo -->

這一份講**寫入端**：任何 session 要記一件事的時候該怎麼放。分層與搬移是**維護端**，在
`memory-hygiene-scan-flow.md` 與 `memory-hygiene-apply-flow.md`。

它以前住在使用者自己機器上的常駐指示檔裡（`~/.claude/CLAUDE.md` 的 Memory Tiering Rules
一節）。那個位置沒有任何閘看得見，於是它指名的三個路徑在框架換層之後全部失效而沒有人
發現。**規矩要跟著執行它的東西走**——消費這些欄位的腳本就在這支 skill 自己的
`scripts/` 底下，所以規矩在這裡。

## 一、先問這件事有沒有資料夾

寫一個新的 memory 檔之前，看 `memory/{topic}/` 在不在：

- **資料夾存在** → 寫進那個資料夾，並且把指標加進那個資料夾自己的 `{topic}/index.md`，
  **不是**加進最上層的 `MEMORY.md`。
- **沒有對應的資料夾** → 寫在 `memory/` 根目錄（扁平層），指標加進 `MEMORY.md` 的 Hot 區。

**不要臨時開新的 topic 資料夾。** 資料夾只由 `memory-hygiene-tiering.py apply` 造。一份
memory 明顯屬於某個還不存在的 topic 時，寫在扁平層，並在 frontmatter 的 `topic:` 填上那個
候選 slug——下一次搬移會把它撿走。

理由是同一句話的兩面：資料夾是搬移的產物，讓寫入端也能造，就有兩個地方在決定「有哪些
topic」，而兩個權威一定會漂。

## 二、Hot 的軟上限是 15

寫完一筆進 `MEMORY.md` 的 Hot 區之後，數一次 `## Hot` 底下有幾條：

- **≤ 15** → 什麼都不用做。
- **> 15** → 告訴使用者：「MEMORY.md Hot 已達 {N} 項，建議跑 `/memory-hygiene` 降級最舊的
  {N-15} 項到 Warm。」

**不要自己搬。** 降級是一個刻意的動作，不是寫入的副作用——寫的人不知道哪一條對明天的人
還有用，而搬錯的那一條不會有人發現。

這條上限守的是一件具體的事：Hot 區長回兩百行的時候，它會在載入時被截斷，而被截掉的那幾行
在畫面上跟不存在長得一樣。

## 三、分層用得到的 frontmatter 欄位

除了基本欄位（`name`、`description`、`metadata.type`）之外，這兩個是給分層用的：

```yaml
pinned: true          # 永遠留在 Hot，不隨衰減降級
topic: cwv-epics      # Warm 資料夾的 slug，用來整批降級
```

- **`pinned` 只由人決定。** 它承載的是「這條不能忘」這個判斷，不要自己加上去。
- **`topic` 推法**：從 `name` / `description` 取最具體的共同標籤（`[acme] AB-478` → `ab-478`、
  「Polaris framework iteration」→ `polaris-framework`）。推不出來就不要填——一個猜出來的
  topic 會把這份 memory 搬進一個沒有人會去翻的資料夾。

這兩個欄位由 `scripts/memory-hygiene-tiering.py` 消費。寫了而沒有跑過分層是無害的：它們
只是還沒被讀到，不會讓任何判定改變。

## 四、寫完之後索引要對得上磁碟

`MEMORY.md` 說的東西必須等於磁碟上有的東西：每個 topic 資料夾都有一行指標、每行的篇數等於
那個資料夾裡非 `{topic}/index.md` 的 `.md` 數、扁平層的每一份都列得到。

**這條對維護動作也成立**，而且維護動作是它比較容易壞的那一邊：一支只掃扁平層的腳本重寫
整份索引時，會把它沒掃到的資料夾一起抹掉。檔案還在磁碟上，但索引是每個 session 唯一會被
載入的那一份——所以那些資料夾等於消失了。渲染那一段的邏輯只有一份
（`render_topic_section`），而它以磁碟為權威。
