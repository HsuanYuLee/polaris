# PRD 範本來源對照

讀了 9 份範本（kuse.ai 那篇加 8 份成熟範本）。2026-10-06 抓取。
下面先列每一份的章節與它特別強調的寫法，最後一張表是章節對照矩陣。

## 每份範本

### K — kuse.ai《PRD 模板》
- 來源：https://www.kuse.ai/zh-tw/blog/tutorials/prd-template
- 章節（「PRD 範本應包含哪些內容」八大部分）：概述與背景脈絡／目標與成功指標／使用者角色與使用情境／功能需求（含驗收標準）／非功能需求／範圍與不在範圍內的項目／相依性、風險與假設／未解問題與未來考量
- 特別強調：範圍要明寫「不在範圍內」與已知取捨；成功要可衡量；相依性與風險要及早揭露並附緩解；另列四種變體（精簡型、技術型、設計導向、高階主管版），高階主管版只談商業影響與策略理由。

### AT — Atlassian Confluence PRD template
- 來源：https://www.atlassian.com/software/confluence/templates/product-requirements
- 章節：PRD Basics and Team Roles（目標發布日、狀態、團隊）／Objective／Success Metrics／Assumptions／Options（需求表：user story、重要程度、JIRA 連結）／Supporting Documentation（原型、圖）／Open Questions（附預計解答日期）／Out of Scope
- 特別強調：Out of Scope 要具體、持續更新，用來擋 scope creep；Assumptions 直接推導需求（假設平板使用者多 → 需求是響應式）；Open Questions 每題帶預計解答日期；整份是單一資訊源。

### LN — Lenny's Product Requirements template（Atlassian 收錄版）
- 來源：https://www.atlassian.com/software/confluence/templates/lennys-product-requirements
- 參考：https://www.lennysnewsletter.com/p/my-favorite-templates-issue-37（Lenny 整理的九份範本）
- 章節：Description（What is it?）／Problem（What problem is this solving?）／Why（How do we know this is real and worth solving?）／Success（How do we know if we've solved it?）／Audience（Who are we building for?）／What（What does this look like in the product?）
- 特別強調：每節就是一個問句，寫的人回答那個問句；問題陳述在設計 review、進度更新、完成前要反覆回看。整理文裡另外點名 Kevin Yien（Square）範本的 Non-Goals 段、Steve Morin（Asana）的成功指標與風險、Adam Thomas 的「保持一頁」。
- 備註：二手整理（prodmgmt.world、figr.design）把 Lenny 的 1-pager 寫成 Problem／Solution／Success Metrics／Scope／Timeline／Open Questions 六段，跟 Atlassian 收錄的原版不同；矩陣採原版。

### AZ — Amazon PR/FAQ（Working Backwards）
- 來源：https://workingbackwards.com/concepts/working-backwards-pr-faq-process/
- 章節：Press Release（Heading／Subheading／Summary Paragraph／Problem Paragraph／Solution Paragraph／Quotes／Getting Started）＋ External FAQ（價格、怎麼運作、支援）＋ Internal FAQ（競爭、市場、技術與法律障礙、財務、成功條件與失敗風險）
- 特別強調：從顧客看得到的結果往回推；用顧客聽得懂的話寫、禁企業術語與架構細節；press release 一頁以內；FAQ 把內部人會問的難題（會怎麼失敗、要花多少）事先寫下來；文件是「找真相」不是「賣案子」。

### GG — Google design doc
- 來源：https://www.industrialempathy.com/posts/design-docs-at-google/
- 章節：Context and scope／Goals and non-goals／The actual design（System-context-diagram、APIs、Data storage、Code and pseudo-code、Degree of constraint）／Alternatives considered／Cross-cutting concerns（安全、隱私）
- 特別強調：Non-goals 的定義——「本來可以合理當成目標、但刻意選擇不做的事」，不是「系統不該當機」這種反向目標；Alternatives considered 寫每個替代方案的取捨、以及取捨怎麼導向最後的選擇；方案沒有歧義、沒有取捨時不該寫 design doc；大案 10–20 頁，小案 1–3 頁。

### AH — Aha! PRD template
- 來源：https://www.aha.io/roadmapping/guide/requirements-management/what-is-a-good-product-requirements-document-template
- 章節（10 steps）：Define the basics（名稱、團隊、發布日、狀態）／Capture strategy／Offer context（客戶訪談、目標客群、用例）／List assumptions／Detail requirements（按優先級的 user stories）／Include design（線框、原型連結）／Provide metrics／Consider impact（相依、對其他功能的影響、維護）／Outline scope（What is not included in this release?）／Make room for questions
- 特別強調：Assumptions 要問「這些假設會怎麼影響開發」；scope 明寫「這一版不含什麼」管理預期；從策略往下推到 release → epic → feature，先爭優先順序再談細節。

### FG — Figma PRD template
- 來源：https://growthx.club/learn/templates/figmas-prd-template（Lenny 整理文亦收錄）
- 章節：Problem Statement／High-level Approach／Goals and Success Metrics／Solution／Key Features／Key Flows／Open Issues and Key Decisions／Key Milestones／Launch Plan
- 特別強調：Key Flows 用圖畫使用者路徑；「Open Issues and Key Decisions」把待決事項獨立成節；里程碑與上市計畫分開寫。

### PP — ProductPlan PRD glossary
- 來源：https://www.productplan.com/glossary/product-requirements-document/
- 章節：Objective/Goal／Features（每項：描述、目標、use case）／UX Flow & Design Notes／System & Environment Requirements／Assumptions, Constraints & Dependencies
- 特別強調：每個功能都附一個使用情境說明使用者怎麼用；UX flow 只給方向不給完整原型；系統環境需求（瀏覽器、OS）獨立一節。

### NT — Notion PRD（ideaplan 整理的 Notion 寫法）
- 來源：https://www.ideaplan.io/blog/how-to-write-a-prd-in-notion（Notion 官方 Ultimate PRD 市集頁只有評分與作者，抓不到章節）
- 章節：Problem Statement（痛點、受影響者、怎麼驗證）／Success Metrics／Scope（含與不含）／User Stories or Requirements（編號）／Edge Cases and Error States／Open Questions／Changelog
- 特別強調：Success Metrics 要有基線、目標、量測時間窗（「整合步驟完成度從 33% 到 55%，上線後 30 天內」）；Open Questions 每題標期限（「sprint 開始前要決定」vs「實作途中可決定」）。

## 章節對照矩陣

欄位代號對應上面九份（含 kuse）：K、AT、LN、AZ、GG、AH、FG、PP、NT。
「✓」是該範本有獨立章節或明確欄位；「△」是併在別節裡提到；「—」是沒有。
最後一欄只算 ✓。

| 章節（本模板用語） | K | AT | LN | AZ | GG | AH | FG | PP | NT | 出現在幾份（✓） |
|---|---|---|---|---|---|---|---|---|---|---|
| 一句話摘要／描述 | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | — | — | 6 |
| 背景與現況 | ✓ | — | ✓ | ✓ | ✓ | ✓ | — | — | — | 5 |
| 問題陳述 | △ | — | ✓ | ✓ | △ | △ | ✓ | — | ✓ | 4 |
| 目標 | ✓ | ✓ | — | — | ✓ | ✓ | ✓ | ✓ | — | 6 |
| 不做的事（non-goals／out of scope） | ✓ | ✓ | — | — | ✓ | ✓ | — | — | ✓ | 5 |
| 使用者／受眾／user stories | ✓ | ✓ | ✓ | △ | — | ✓ | ✓ | ✓ | ✓ | 7 |
| 方案（solution／requirements） | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | 9 |
| 替代方案與取捨 | — | — | — | △ | ✓ | — | — | — | — | 1 |
| 需要決定的事（key decisions） | — | — | — | — | — | — | ✓ | — | — | 1 |
| 里程碑／時程／上線 | — | △ | — | △ | — | △ | ✓ | — | — | 1 |
| 成功指標 | ✓ | ✓ | ✓ | △ | — | ✓ | ✓ | — | ✓ | 6 |
| 假設 | ✓ | ✓ | — | — | — | ✓ | — | ✓ | — | 4 |
| 風險與相依 | ✓ | — | — | ✓ | △ | ✓ | — | ✓ | — | 4 |
| 開放問題 | ✓ | ✓ | — | ✓ | — | ✓ | ✓ | — | ✓ | 6 |
| 技術附錄（API、資料、環境、edge cases） | ✓ | — | — | — | ✓ | — | — | ✓ | ✓ | 4 |
| 設計／流程圖／原型附件 | — | ✓ | — | — | ✓ | ✓ | ✓ | ✓ | — | 5 |
| 狀態／變更紀錄 | — | ✓ | — | — | — | ✓ | — | — | ✓ | 3 |

## 從矩陣讀出來的三件事

1. **九份全有的只有「方案」**，其次是使用者（7）、摘要／目標／成功指標／開放問題（各 6）。這五樣是任何讀者都預期看到的，模板不省。
2. **「需要決定的事」與「替代方案的取捨」幾乎沒有範本獨立成節**（各 1 份）。Google 把取捨放在 alternatives considered，給工程師看。本模板照這個做法：正文只寫採用的做法，比較過的方案放附錄 D；還沒人確認的前提列在〈待確認事項〉，每項寫不成立時會改什麼（Atlassian、Notion 的 open questions 都帶負責人與期限）。2026-10-06 之前的版本把它寫成「要讀者決定的題目」，被退回，原話是「這是 PRD，請你假設，這份文件建立的當下，就是要這麼做了」。
3. **時程幾乎都只是一個欄位**（目標發布日），只有 Figma 獨立成里程碑。本模板把它升成一節，因為讀者要靠它判斷「什麼時候會看到」，而班次（release train）是這裡上線的實際單位。

## 寫法上被反覆強調、本模板採用的

- Non-goals 是「本來可以做但刻意不做」，不是反向目標（Google）。
- 成功指標要有基線、目標值、量測時間窗（Notion／ideaplan），只挑一個主指標（Notion 寫法整理）。
- Open questions 每題標期限或負責人（Atlassian 帶日期、Notion 帶「什麼時候前要決定」）。
- 寫給非工程師看：禁術語與架構細節、一頁以內講完（Amazon press release、Lenny 的「保持一頁」）。
- 內部人會問的難題事先寫下來，包括會怎麼失敗（Amazon internal FAQ）。
- 每個方案附使用情境或流程圖（ProductPlan、Figma key flows）。
- 沒有取捨、沒有歧義的事不寫長文（Google）——對應本模板的「同一件事只講一次」與長度上限。

## 排版、流程圖、時間軸的出處

2026-10-06 補進模板〈排版〉〈流程圖〉〈時間軸〉三節時讀的來源。〈排版〉每條規則後面的代號對到這裡。

### 排版

| 代號 | 來源 | 取了什麼 |
|---|---|---|
| M | 邱韜誠〈[Medium 中文排版建議：讓你文章更加「鬆軟」的排版技巧－－區塊式排版法](https://medium.com/%E8%AD%B0%E9%A1%8C%E6%89%93%E5%AD%97%E6%A9%9F/medium-%E4%B8%AD%E6%96%87%E6%8E%92%E7%89%88%E5%BB%BA%E8%AD%B0-%E8%AE%93%E4%BD%A0%E6%96%87%E7%AB%A0%E6%9B%B4%E5%8A%A0-%E9%AC%86%E8%BB%9F-%E7%9A%84%E6%8E%92%E7%89%88%E6%8A%80%E5%B7%A7-%E5%8D%80%E5%A1%8A%E5%BC%8F%E6%8E%92%E7%89%88%E6%B3%95-16601ca616d6)〉（2017-12-07） | 一塊一件事、區塊之間留白、每個大段落有一張圖讓眼睛休息、用大小標收攏區塊、重點才強調 |
| R | 阮一峰《[中文技術文件寫作規範](https://github.com/ruanyf/document-style-guide)》〈標題〉〈文本〉〈段落〉 | 標題層級不跳、下級不重複上級的字、少用第四級、句長上限、一段一個主題且中心句在前 |
| S | 《[中文文案排版指北](https://github.com/sparanoid/chinese-copywriting-guidelines)》 | 中英數之間的空格、全形標點、半形數字、專有名詞大小寫 |
| G | Google developer documentation style guide 的 [headings](https://developers.google.com/style/headings)、[lists](https://developers.google.com/style/lists)、[tables](https://developers.google.com/style/tables)、[link text](https://developers.google.com/style/link-text) | 標題下先接文字、編號與項目符號的分工、三個屬性以上才用表、表前一句引言、不合併儲存格、連結文字要說出目的地 |

M 的作者在文末更新裡自己寫明「沒有經過嚴謹驗證」，也收到過「反而更凌亂」的回饋。所以模板只取它跟 R、G 方向一致的部分（切塊、留白、標題收攏），不取它特有的分隔線與引號用法。

### 流程圖

| 記法 | 規範 | 模板用到的符號 |
|---|---|---|
| 一般流程圖 | [ISO 5807:1985](https://www.iso.org/standard/11955.html) Information processing — Documentation symbols and conventions for data, program and system flowcharts | 端點（圓角框）、處理（矩形）、判斷（菱形）、資料（平行四邊形） |
| 泳道圖 | OMG [BPMN 2.0.2](https://www.omg.org/spec/BPMN/2.0.2/) | pool 與 lane、開始與結束事件、工作、閘道 |
| 循序圖 | OMG [UML 2.5.1](https://www.omg.org/spec/UML/2.5.1/) 第 17 章 Interactions | 生命線、同步訊息、回應訊息 |
| 狀態圖 | OMG UML 2.5.1 第 14 章 State Machines | 初始狀態、狀態、帶事件的轉移、終止狀態 |

Mermaid 的寫法對照 [flowchart](https://mermaid.js.org/syntax/flowchart.html)、[sequenceDiagram](https://mermaid.js.org/syntax/sequenceDiagram.html)、[stateDiagram](https://mermaid.js.org/syntax/stateDiagram.html)。Mermaid 沒有 BPMN 記法，模板用 subgraph 當泳道，完整 BPMN 符號指向 [bpmn.io](https://bpmn.io/)。

### 時間軸

| 來源 | 取了什麼 |
|---|---|
| PMI《PMBOK 指南》的時程表示法 | 長條圖（Gantt）表示活動的起訖，里程碑是長度為零的時間點 |
| Mermaid [gantt](https://mermaid.js.org/syntax/gantt.html) | `dateFormat`、`section`、`after` 依賴、`milestone` 的寫法 |

甘特圖沒有 ISO 或 OMG 那種符號標準，所以欄位以 PMBOK 的定義為準。

### 圖表標號、文件資訊、閱讀引導

| 代號 | 來源 | 取了什麼 |
|---|---|---|
| T | 國立臺灣大學政治學系〈[論文寫作參考格式](https://ntupoli.s3.amazonaws.com/wp-content/uploads/2010/02/%E8%AB%96%E6%96%87%E6%A0%BC%E5%BC%8F982.pdf)〉（民國 99 年）、國立嘉義大學師範學院《[博碩士論文格式撰寫參考手冊](https://website.ncyu.edu.tw/coledu/ServerFile/Get/04a59ebc-a599-42dc-be55-20692233f1e1?nodeId=41733&sId=95416)》（2022） | 表題在表的上方、圖題在圖的下方；圖表內文字可以比內文小 |
| 本 | 2026-10-06 一份開發計畫被退回時的原話 | 文件資訊表照台灣企劃書慣例（文件名稱、版本、日期、撰寫人、審閱人、狀態），人名用團隊內溝通時的名字；〈本文件怎麼讀〉按讀者指路；每章開頭一句說給誰看 |

字級層級（〈排版〉表 5）的倍數取自常見網頁內文 16px 的層級做法，不是某一份標準；要點是層級之間分得出來，並且每段只屬於一層。

### 發布處做不到就換

〈排版〉的字級、圖說、附註是與平台無關的規格。2026-10-06 那一份計畫在 Claude Docs 上發布，段落只有標題與內文兩種字級、圖片下方沒有原生圖說，於是圖說與圖之間空一行、附註混在內文裡，被判不合格。所以模板寫明：平台做不到其中任何一項就換平台，例如改成 HTML 頁，用 `<figure>`、`<figcaption>`、`<caption>` 與 CSS 做出層級。
