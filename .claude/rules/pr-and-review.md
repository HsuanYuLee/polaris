# PR & Review Conventions

Universal review rules. Apply to all companies and projects.

## Review Comment Format

- **必須用 inline comments**：review findings 必須以 inline comment 指向具體 file + line，不可全部塞進 review body。Review body 只放 1-2 句簡短總結
- **Review body 範例**：「整體架構清晰，2 項待確認（見 inline comments）」
- **禁止**：把所有 findings 用 markdown 清單寫進 review body 當總結報告

## Review Language

- **Review 語言必須跟隨 PR description 的主要語言**：PR description 用中文寫，review 就用中文回應；用英文寫就用英文回應
- 若 PR description 混合語言，以佔比較多的語言為準
- 技術術語（function name、variable name、框架概念）維持原文不需翻譯
