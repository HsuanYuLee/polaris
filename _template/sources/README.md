# sources —— 這是你的 repo，不是框架的

每個 source 是一份文件：凍結塊（這件事成功的定義，只有人能改）＋ 活文件（所有階段都寫它）。
它記的是**你**在做什麼、為什麼這樣定義成功、路上撞到什麼。用同一套框架的另一個人，這裡的
內容完全不一樣。

所以這個目錄由你自己版控。框架 repo 忽略它，template 只提供空殼。

## 為什麼仍然是一個 git repo

因為凍結 ＝ commit。封條（`frozen_by` / `assertions_hash`）只證明 fence 內文與 frontmatter
自洽——改了 fence 再重簽一次，封條一樣自洽，而 `--by` 只是一個字串。真正擋住偷改的是 git
歷史：`frozen-assertion-fence.sh verify` 預設把 fence 內文與該檔在 HEAD 的版本比對，不同就
fail-closed。

沒有 git，`verify` 會回 `POLARIS_FROZEN_FENCE_HISTORY_UNAVAILABLE`——放在未追蹤的位置買不回
豁免。

## 開始

```bash
cp _template/sources/README.md sources/README.md
cp _template/sources/gitignore.example sources/.gitignore
cd sources && git init
git add . && git commit -m "sources: 開始"
```

要不要推到 remote 由你決定。框架不需要知道它在哪裡，只需要它有歷史。

## 目錄形狀

```
sources/
  {source-name}/
    index.md                       正文含凍結塊，其餘是活文件
    .spine/loop-state.json         輪次（機器寫，不進歷史）
    .spine/measurement-ledger.json 量測命令登錄（機器寫，不進歷史）
```
