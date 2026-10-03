# Issue template

The body of an Issue that a human can later hand to a topic chat with
"`<repo>#<number>` をやって". Create it with `gh issue create -R <owner/repo>
--title "<title>" --body-file <file>`; the topic chat writes the file, and the
human only says "make this an Issue".

This is not a `.github/ISSUE_TEMPLATE/`: apm cannot deploy that directory, and
`/.github/` is stage C in every repo, so a copy there would cost four admin
merges per edit. The web form is not offered; Issues are made from the chat.

```markdown
## 目的
<1 文。人の言葉で>

## 完了条件
- [ ] <観察できる条件>

## 対象
リポジトリ: <owner/repo>
パス: <触ってよい範囲>

## 段階の見込み
<A | B | C>（見込み。正は必須チェック `ci / stage C paths`）

## 対象外
- <しないこと>

<!-- 親: <URL>（あれば） -->
```

## Filling it

- One Issue, one repository. Work across repositories is a parent Issue with
  sub-issues, each carrying the parent's URL in the last line.
- 目的 and 完了条件 are the human's words. If either cannot be written yet, the
  work is still a topic to ground, not an Issue (`SKILL.md`, "Topic chat").
- 段階の見込み is a guess from `docs/gates.md`. The required check
  `ci / stage C paths` decides; a wrong guess changes nothing.
- Do not add the `agent:go` label. Only the human adds it ("Run an Issue" in
  `SKILL.md`), and `triage:*` labels are not a substitute.

## When the five items are all filled

`grounding.md` skips the grilling for an Issue that carries all five items and
asks the human once, through `ExitPlanMode`. A missing item is grounded the
usual way.
