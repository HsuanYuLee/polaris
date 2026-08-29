# issues —— 這是你的 repo，不是框架的

每張單是一份文件：凍結塊（這件事成功的定義，只有人能改）＋ 可以改的那部分（所有階段都寫它）。
它記的是**你**在做什麼、為什麼這樣定義成功、路上撞到什麼。用同一套框架的另一個人，這裡的
內容完全不一樣。

所以這個目錄由你自己版控。框架 repo 忽略它，template 只提供空殼。

## 為什麼仍然是一個 git repo

因為凍結 ＝ commit。校驗值（`frozen_by` / `assertions_hash`）只證明 fence 內文與 frontmatter
自洽——改了 fence 再重簽一次，校驗值一樣對得上，而 `--by` 只是一個字串。真正擋住偷改的是 git
歷史：`frozen-assertion-fence.sh verify` 預設把 fence 內文與該檔在 HEAD 的版本比對，不同就
fail-closed。

沒有 git，`verify` 會回 `POLARIS_FROZEN_FENCE_HISTORY_UNAVAILABLE`——放在未追蹤的位置買不回
豁免。

## 開始

```bash
cp .claude/skills/refinement/templates/issues/README.md issues/README.md
git -C issues init
git -C issues add . && git -C issues commit -m "issues: 開始"
```

要不要推到 remote 由你決定。框架不需要知道它在哪裡，只需要它有歷史。

## 目錄形狀

```
issues/
  {命名空間}/                        自己的框架工作、某個公司、某個專案——你決定怎麼分
    {單號}/
      index.md                       正文含凍結塊，其餘是可以改的部分
      .spine/loop-state.json         輪次
      .spine/measurement-ledger.json 量測命令登錄
      .spine/evidence/{assertion}.json    oracle 留下的證據
      .spine/delivery.json           交付紀錄（判定 PASS 之後才寫得下去）
    archive/
      {單號}/                        收斂完的搬到這裡，由流程自己搬
```

命名空間叫什麼**不影響任何判定**。`archive-delivered-issues.sh` 逐個走過去，不從名字推導
行為——用名字判斷身分是這套框架一路禁止的形狀。

`.spine/` 整個進歷史。量測命令、證據、輪次、交付紀錄就是「我們怎麼知道它是真的」那一半的
知識；把它們留在工作目錄裡，一張單就搬不動了。
