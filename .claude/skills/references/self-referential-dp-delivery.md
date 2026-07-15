# Self-Referential DP Delivery

自指 DP（self-referential DP）指「交付物本身就是 delivery gate 的 fix」的 framework DP：
它的 planned task Allowed Files 與 delivery flow 會 invoke 的 gate / hook / validator（或其
依賴 lib）相交。這類 DP 一 push 就會被**舊版**（正在被修的那條）gate 誤擋，形成「要 merge
先過 gate、gate 就是壞的」的 deadlock。

本 reference 是自指 DP sanctioned 交付路徑的 **canonical single source**：終局是 D1
deterministic 自驗（新版 gate 自我識別 + governed selftest corpus 綠燈放行）；D1 尚未落地或
無法自我交付時，D2 有界 bootstrap 手動交付是**唯一**登記在案的過渡 carve-out。此 carve-out
必須帶 owner、removal criteria、與 auto-pass 對等的 evidence，不是穩態、不是 blanket bypass。

對齊 `canonical-contract-governance.md`（Strong constraints first / Allowed Exceptions）、
`contract-design.md` Heuristic 1（A 類 gateable invariant 不接受 prose-only）、
`framework-iteration.md`（Target-State First）。owning DP：DP-419。

## 觸發條件

一張 DP 判定為自指 delivery gate，當且僅當它的 planned task Allowed Files 與
**delivery-gate script set** 相交。script set 的單一來源（D4）：

- `scripts/manifest.json` 中 `kind=gate` 或 `kind=hook` 的 script。
- delivery lane 進入點：`.claude/hooks/pre-push-quality-gate.sh`、
  `scripts/check-framework-pr-gate.sh`、`scripts/framework-release-pr-lane.sh`。
- 上述 script 沿 source 依賴展開命中的 `scripts/lib/*.sh`（多層自指：改的是 gate 依賴的
  lib 而非 gate 本體，仍算自指）。

判定必須機械化（見 D1 classifier `scripts/detect-self-referential-delivery.sh`），不靠人讀
檔名比對。非自指 DP（Allowed Files 與 script set 不相交）**不**走本 carve-out，一律走標準
`engineering -> framework-release` 交付。

兩個自指窗口都涵蓋：

1. **push / PR-gate 窗口**：舊版 gate 從主 checkout 打在 worktree 的新版改動上而誤擋。
2. **framework-release promotion-後 tail 窗口**（D5）：promotion 之後 tail helper 跑到自己
   剛 merge 的新版；新版若有 bug 會炸 closeout。

## 自驗步驟

自指交付放行的 trust 錨定是「新版通過完整 governed selftest corpus」，**不**加 human
sign-off（額外人工關卡本身又是會卡住 / 被遺忘的閘，與「自迭代不被卡」相斥）。步驟：

1. 在 engineering task worktree 內，對改動跑**新版** gate（worktree 內即新版），確認新版
   對本改動自洽通過。
2. 跑完整 governed selftest corpus：`bash scripts/run-aggregate-selftests.sh`，必須全綠。
   corpus 較難一次騙過，是比單一 gate 更難偽造的 regression 錨點（涵蓋所有 governed
   selftest，保護其他 DP 的 delivery 不被這次 gate fix regress）。
3. framework-release tail 窗口（D5）：新版 tail helper 必須以 **promotion 前** 的 corpus
   綠燈為前提；promotion 前 corpus 非綠則 tail fail-closed、不 promote。
4. 新版 gate 自驗 + corpus 綠燈皆成立，才進入手動交付；任一不成立即停止，不繞過。

## 繞過邊界

carve-out 只允許在最小必要範圍內繞過**舊版**誤擋，防止洗白「本來就該被擋」的改動：

- **僅限舊版誤擋的窄範圍**：繞過只針對「舊版 gate 對這次 gate fix 的 false block」，且新版
  gate 必須通過；新版 gate 也拒絕的改動**不得**交付（carve-out 不是交付壞改動的洗白口）。
- **改動範圍限於 gate fix 本身**：blast radius 限定在被修的 gate / lib；夾帶無關改動不適用
  本 carve-out。
- **git-native 路徑**：以正常 git commit / push / PR 交付，並記 log 說明繞過的是哪一條舊版
  gate、為何誤擋；不使用非 git 的旁路寫入。
- **禁 bypass env**：**不得**新增或使用 `POLARIS_*_BYPASS`（如
  `POLARIS_SKILL_BOUNDARY_BYPASS` / `POLARIS_LANGUAGE_POLICY_BYPASS`）作為通用逃生口；
  bypass env 一律不得 silence gate。
- **登記在案**：每次自指手動交付都要在 owning DP / active-thread 記 owner、繞過的 gate、
  removal criteria 指回 D1。

## Evidence Checklist

手動交付**必須**產出與 auto-pass 交付對等的 evidence marker，不接受 evidence-gapped 交付
（DP-417 手動交付 evidence 全缺即反例）。每項對照 auto-pass 對等來源：

- **completion_gate marker**（status=PASS）：`.polaris/evidence/completion-gate/` —— 與
  engineering completion gate 對等。
- **Layer B verify marker**：`run-verify-command.sh` 產出的 verify evidence marker —— 與
  auto-pass verify 階段對等。
- **pr_freshness marker**：base freshness 事實 —— 與 engineering delivery backbone 對等。
- **ci_local marker**：framework repo 無 ci-local 時標 N/A，其餘與 ci-local gate 對等。
- **delivery head sha**：task.md `deliverable.head_sha` delivery block（DP-360 唯一交付 head
  authority）—— 與 auto-pass 交付 head 對等，**不**回退 branch ref。
- **closeout evidence**：task move 進 `tasks/pr-release/` + status `IMPLEMENTED`，經唯一
  writer `scripts/mark-spec-implemented.sh` —— 與 auto-pass closeout chain 對等。

parity 由 `scripts/selftests/self-referential-manual-delivery-evidence-parity-selftest.sh`
（DP-419 T5）機械斷言：手動交付路徑產出的 marker 集合與 auto-pass 交付對等，無 gap。

## Removal Criteria（D2 退役條件）

- **owner**：framework maintainer。
- **removal criteria**：D1 deterministic 自指識別 gate（`detect-self-referential-delivery.sh`
  + 自驗放行 wiring）落地並綠燈，能自我交付後續自指 DP。
- **follow-up**：移除手動步驟、只留 deterministic 路徑；D1 綠燈後本 D2 手動 carve-out 依此
  退役，不作穩態保留。
