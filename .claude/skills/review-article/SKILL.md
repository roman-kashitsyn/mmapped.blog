---
name: review-article
description: >
  Review a technical article written in classical style.
  Use when the user asks to review, proofread, or critique a blog post or essay (.tex file).
  Checks prose quality, argument structure and clarity.
disable-model-invocation: true
allowed-tools: Read Grep Glob
arguments:
  - name: file
    required: false
    description: Path to the .tex file to review. If omitted, review the article with unstaged changes.
argument-hint: "[path/to/article.tex]"
---

# Technical Article Review

You are reviewing a technical article written in classical nonfiction style: clear, opinionated, concise prose that blends engineering depth with literary craft.
The author values brevity, wit, precise word choice, and strong analogies.
Articles use LaTeX with a custom document class.

## How to find the article

If `$file` is provided, review that file. Otherwise, run `git diff --name-only` and look for modified `.tex` files under `posts/`.

## Review process

Read the entire article first, then provide feedback organized into these sections:

### 1. Argument and structure

- Is the thesis clear and stated early?
- Does each section advance the argument or earn its place?
- Are transitions between sections smooth?
- Does the ending land? (Avoid trailing off or restating the obvious.)
- Flag sections that feel like filler or that repeat a point already made.

### 2. Prose quality

- Flag verbose or flabby sentences. Suggest tighter rewrites.
- Flag clichés, weasel words ("very", "really", "quite", "somewhat", "arguably"), and hedge phrases ("it could be said that", "one might argue").
- Flag passive voice where active would be stronger.
- Flag sentences longer than ~30 words that could be split.
- Note sentences or passages that are particularly good—the author wants to know what works, not just what doesn't.
- Check that the tone is consistent throughout (no sudden shifts to casual or academic register).

### 3. Clarity and precision

- Flag jargon used without sufficient context for the target audience.
- Flag ambiguous pronouns or referents.
- Flag claims that need evidence, citation, or qualification.
- Flag logical gaps or non-sequiturs.

### 4. Formatting

- Check for typos, spelling errors, and grammar issues.
- Flag overly long paragraphs (more than ~8-10 lines of source) that could benefit from a break.

## Output format

For each issue, quote the relevant passage and provide a concrete suggestion.
Group minor issues (typos, small grammar fixes) into a list at the end.

Open with a 2-3 sentence overall impression.
Close with a short list of the article's strengths.

Do NOT rewrite the article.
Provide targeted, actionable feedback.
Respect the author's voice—suggest improvements that sound like the author, not like you.
