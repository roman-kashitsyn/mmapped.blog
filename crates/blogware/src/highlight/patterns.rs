//! Patterns over tokens that the languages build their rules from.

use rftex_doc::document::HighlightRole as Role;

use super::lexer::{is_newline, Kind, Token};

pub(super) fn is_trivia(token: &Token) -> bool {
    matches!(token.kind, Kind::Whitespace | Kind::Comment)
}

pub(super) fn is_ident(token: &Token) -> bool {
    token.kind == Kind::Ident
}

pub(super) fn has_newline(token: &Token) -> bool {
    token.text.bytes().any(is_newline)
}

/// Gives a name its role. Only identifiers and keywords can be names.
pub(super) fn mark(token: &mut Token, role: Role) {
    if matches!(token.kind, Kind::Ident | Kind::Keyword) {
        token.role = Some(role);
    }
}

/// The first token at or after `i` that is not trivia.
pub(super) fn next_sig_from(tokens: &[Token], i: usize) -> Option<usize> {
    (i..tokens.len()).find(|&j| !is_trivia(&tokens[j]))
}

pub(super) fn next_sig(tokens: &[Token], i: usize) -> Option<usize> {
    next_sig_from(tokens, i + 1)
}

pub(super) fn prev_sig(tokens: &[Token], i: usize) -> Option<usize> {
    (0..i).rev().find(|&j| !is_trivia(&tokens[j]))
}

/// The index of the token that closes the one at `open_idx`.
pub(super) fn matching_forward(
    tokens: &[Token],
    open_idx: usize,
    open: &str,
    close: &str,
) -> Option<usize> {
    if tokens.get(open_idx)?.text != open {
        return None;
    }
    let mut depth = 0i32;
    for (i, token) in tokens.iter().enumerate().skip(open_idx) {
        if token.text == open {
            depth += 1;
        } else if token.text == close {
            if depth == 1 {
                return Some(i);
            }
            depth -= 1;
        }
    }
    None
}

/// A balanced group that starts at the first significant token from `i`:
/// its opener, its closer and the index after it.
pub(super) fn balanced_from(
    tokens: &[Token],
    i: usize,
    open: &str,
    close: &str,
) -> Option<(usize, usize, usize)> {
    let open_idx = next_sig_from(tokens, i)?;
    if tokens[open_idx].text != open {
        return None;
    }
    let close_idx = matching_forward(tokens, open_idx, open, close)?;
    Some((open_idx, close_idx, close_idx + 1))
}

pub(super) fn mark_next_ident(tokens: &mut [Token], role: Role, i: usize) -> Option<usize> {
    let id = next_sig_from(tokens, i)?;
    if !is_ident(&tokens[id]) {
        return None;
    }
    mark(&mut tokens[id], role);
    Some(id + 1)
}

pub(super) fn step_depth(depth: usize, token: &Token) -> usize {
    match token.text {
        "(" | "[" | "{" => depth + 1,
        ")" | "]" | "}" => depth.saturating_sub(1),
        _ => depth,
    }
}

pub(super) fn find_top_level_comma_or_end(tokens: &[Token], start: usize, stop: usize) -> usize {
    let mut depth = 0;
    for i in start..stop {
        if depth == 0 && tokens[i].text == "," {
            return i;
        }
        depth = step_depth(depth, &tokens[i]);
    }
    stop.max(start)
}

/// Splits `start..stop` at top-level semicolons and line breaks.
pub(super) fn segment_boundaries(
    tokens: &[Token],
    start: usize,
    stop: usize,
) -> Vec<(usize, usize)> {
    let mut segments = Vec::new();
    let mut seg_start = start;
    let mut depth = 0;
    for i in start..stop {
        let token = &tokens[i];
        if depth == 0 && (token.text == ";" || has_newline(token)) {
            segments.push((seg_start, i));
            seg_start = i + 1;
            depth = 0;
        } else {
            depth = step_depth(depth, token);
        }
    }
    segments.push((seg_start, stop.max(seg_start)));
    segments
}

#[derive(Clone, Copy)]
pub(super) enum Style {
    /// One name, as in `type Name ...`.
    FirstName,
    /// A list of names, as in `var a, b int`.
    NameList,
}

pub(super) fn mark_segment(
    tokens: &mut [Token],
    style: Style,
    role: Role,
    start: usize,
    stop: usize,
) {
    let Some(first) = next_sig_from(tokens, start) else {
        return;
    };
    if first >= stop || !is_ident(&tokens[first]) {
        return;
    }
    mark(&mut tokens[first], role);
    if let Style::FirstName = style {
        return;
    }
    let mut last = first;
    while let Some(comma) = next_sig(tokens, last) {
        if comma >= stop || tokens[comma].text != "," {
            break;
        }
        match next_sig(tokens, comma) {
            Some(id) if id < stop && is_ident(&tokens[id]) => {
                mark(&mut tokens[id], role);
                last = id;
            }
            _ => break,
        }
    }
}

/// Marks the names of a Go parameter or field list.
pub(super) fn mark_go_field_vars(
    tokens: &mut [Token],
    open_idx: usize,
    close_idx: usize,
    role: Role,
) {
    let mut i = open_idx + 1;
    loop {
        let Some(field) = next_sig_from(tokens, i) else {
            return;
        };
        if field >= close_idx {
            return;
        }
        let field_end = if is_ident(&tokens[field]) {
            let mut names = vec![field];
            let mut type_start = None;
            let mut last = field;
            loop {
                match next_sig(tokens, last) {
                    Some(comma) if comma < close_idx && tokens[comma].text == "," => {
                        match next_sig(tokens, comma) {
                            Some(id) if id < close_idx && is_ident(&tokens[id]) => {
                                names.push(id);
                                last = id;
                            }
                            _ => break,
                        }
                    }
                    Some(j) if j < close_idx => {
                        type_start = Some(j);
                        break;
                    }
                    _ => break,
                }
            }
            match type_start {
                Some(j) if tokens[j].text != "." => {
                    for name in names {
                        mark(&mut tokens[name], role);
                    }
                    find_top_level_comma_or_end(tokens, j, close_idx)
                }
                _ => find_top_level_comma_or_end(tokens, field, close_idx),
            }
        } else {
            find_top_level_comma_or_end(tokens, field, close_idx)
        };
        i = field_end + 1;
    }
}

/// Splits `start..stop` at top-level commas and calls `mark_piece` on each
/// piece, the last one included even if it is empty.
pub(super) fn for_each_comma_segment(
    tokens: &mut [Token],
    start: usize,
    stop: usize,
    step: fn(usize, &Token) -> usize,
    mut mark_piece: impl FnMut(&mut [Token], usize, usize),
) {
    let mut seg_start = start;
    let mut depth = 0;
    for i in start..stop {
        if depth == 0 && tokens[i].text == "," {
            mark_piece(tokens, seg_start, i);
            seg_start = i + 1;
            depth = 0;
        } else {
            depth = step(depth, &tokens[i]);
        }
    }
    mark_piece(tokens, seg_start, stop);
}

pub(super) fn step_rust_type_depth(depth: usize, token: &Token) -> usize {
    match token.text {
        "(" | "[" | "{" | "<" => depth + 1,
        ")" | "]" | "}" | ">" => depth.saturating_sub(1),
        _ => depth,
    }
}

/// Marks the names of a Rust parameter list: the first identifier of each
/// parameter, after an optional `mut`.
pub(super) fn mark_rust_field_vars(
    tokens: &mut [Token],
    open_idx: usize,
    close_idx: usize,
    role: Role,
) {
    for_each_comma_segment(
        tokens,
        open_idx + 1,
        close_idx,
        step_rust_type_depth,
        |tokens, start, stop| match next_sig_from(tokens, start) {
            Some(mut_idx) if mut_idx < stop && tokens[mut_idx].text == "mut" => {
                if let Some(id) = next_sig(tokens, mut_idx) {
                    if id < stop && is_ident(&tokens[id]) {
                        mark(&mut tokens[id], role);
                    }
                }
            }
            Some(id) if id < stop && is_ident(&tokens[id]) => mark(&mut tokens[id], role),
            _ => {}
        },
    );
}

/// Marks the names of a C parameter list: the last top-level identifier of
/// each parameter.
pub(super) fn mark_c_field_vars(
    tokens: &mut [Token],
    open_idx: usize,
    close_idx: usize,
    role: Role,
) {
    for_each_comma_segment(
        tokens,
        open_idx + 1,
        close_idx,
        step_depth,
        |tokens, start, stop| {
            let mut last = None;
            let mut depth = 0;
            for i in start..stop {
                if depth == 0 && is_ident(&tokens[i]) {
                    last = Some(i);
                }
                depth = step_depth(depth, &tokens[i]);
            }
            if let Some(i) = last {
                mark(&mut tokens[i], role);
            }
        },
    );
}

/// The index of the token that starts the statement holding token `i`, or
/// `None` if it is the first statement.
pub(super) fn statement_boundary_before(tokens: &[Token], i: usize) -> Option<usize> {
    let mut j = prev_sig(tokens, i)?;
    loop {
        let token = &tokens[j];
        if has_newline(token) || matches!(token.text, ";" | "{" | "}" | "(") {
            return Some(j);
        }
        if token.kind == Kind::Keyword
            && matches!(
                token.text,
                "if" | "for" | "switch" | "select" | "case" | "match"
            )
        {
            return Some(j);
        }
        j = j.checked_sub(1)?;
    }
}

/// Marks the variables that `:=` at `op_idx` declares.
pub(super) fn mark_short_decl_lhs(tokens: &mut [Token], op_idx: usize, role: Role) {
    let start = statement_boundary_before(tokens, op_idx).map_or(0, |j| j + 1);
    let mark_piece = |tokens: &mut [Token], a: usize, b: usize| {
        let mut count = 0;
        let mut ident = None;
        let mut depth = 0;
        for i in a..b {
            if depth == 0 && is_ident(&tokens[i]) {
                count += 1;
                ident = Some(i);
            }
            depth = step_depth(depth, &tokens[i]);
        }
        if let (1, Some(i)) = (count, ident) {
            mark(&mut tokens[i], role);
        }
    };
    for_each_comma_segment(tokens, start, op_idx, step_depth, mark_piece);
}

pub(super) fn find_statement_stop(tokens: &[Token], start: usize) -> usize {
    (start..tokens.len())
        .find(|&i| matches!(tokens[i].text, ";" | "}") || has_newline(&tokens[i]))
        .unwrap_or(tokens.len())
}

/// A declaration with a parenthesized list of specs: `const ( ... )`.
pub(super) fn apply_decl_segments(
    tokens: &mut [Token],
    style: Style,
    role: Role,
    i: usize,
) -> Option<usize> {
    let open_idx = next_sig_from(tokens, i)?;
    if tokens[open_idx].text != "(" {
        return None;
    }
    let close_idx = matching_forward(tokens, open_idx, "(", ")")?;
    for (start, stop) in segment_boundaries(tokens, open_idx + 1, close_idx) {
        mark_segment(tokens, style, role, start, stop);
    }
    Some(close_idx + 1)
}

pub(super) fn apply_decl_choice(tokens: &mut [Token], style: Style, role: Role, i: usize) {
    if apply_decl_segments(tokens, style, role, i).is_some() {
        return;
    }
    if let Some(start) = next_sig_from(tokens, i) {
        let stop = find_statement_stop(tokens, start);
        mark_segment(tokens, style, role, start, stop);
    }
}

pub(super) fn find_top_level(tokens: &[Token], start: usize, delim: &str) -> Option<usize> {
    let mut depth = 0;
    for i in start..tokens.len() {
        if depth == 0 && tokens[i].text == delim {
            return Some(i);
        }
        depth = step_depth(depth, &tokens[i]);
    }
    None
}

pub(super) fn first_top_level_token(tokens: &[Token], start: usize, stop: usize) -> Option<usize> {
    let mut depth = 0;
    for i in start..stop {
        if depth == 0 && !is_trivia(&tokens[i]) {
            return Some(i);
        }
        depth = step_depth(depth, &tokens[i]);
    }
    None
}

/// `let name ... =` in OCaml: a value if nothing but a pattern precedes the
/// `=`, a function otherwise.
pub(super) fn apply_ocaml_value_binding(tokens: &mut [Token], i: usize) -> Option<usize> {
    let name_idx = next_sig_from(tokens, i)?;
    if !is_ident(&tokens[name_idx]) {
        return None;
    }
    let eq_idx = find_top_level(tokens, name_idx + 1, "=")?;
    match first_top_level_token(tokens, name_idx + 1, eq_idx) {
        None => mark(&mut tokens[name_idx], Role::Variable),
        Some(j) if matches!(tokens[j].text, "," | ":") => {
            // A tuple or a type annotation: every name up to the colon.
            let mut depth = 0;
            for k in name_idx..eq_idx {
                if depth == 0 && tokens[k].text == ":" {
                    break;
                }
                if depth == 0 && is_ident(&tokens[k]) {
                    mark(&mut tokens[k], Role::Variable);
                }
                depth = step_depth(depth, &tokens[k]);
            }
        }
        Some(_) => mark(&mut tokens[name_idx], Role::Defun),
    }
    Some(eq_idx + 1)
}

pub(super) fn apply_c_function_definition(tokens: &mut [Token], i: usize) {
    let Some(name_idx) = next_sig_from(tokens, i) else {
        return;
    };
    if !is_ident(&tokens[name_idx]) {
        return;
    }
    // Not a member access or a preprocessor directive.
    if let Some(prev) = prev_sig(tokens, name_idx) {
        if matches!(tokens[prev].text, "." | "->" | "#") {
            return;
        }
    }
    let Some(open_idx) = next_sig(tokens, name_idx) else {
        return;
    };
    if tokens[open_idx].text != "(" {
        return;
    }
    let Some(close_idx) = matching_forward(tokens, open_idx, "(", ")") else {
        return;
    };
    if next_sig(tokens, close_idx).is_some_and(|body| tokens[body].text == "{") {
        mark(&mut tokens[name_idx], Role::Defun);
        mark_c_field_vars(tokens, open_idx, close_idx, Role::Variable);
    }
}

pub(super) fn apply_c_typedef_declaration(tokens: &mut [Token], i: usize) {
    let Some(stop) = find_top_level(tokens, i, ";") else {
        return;
    };
    let mut last = None;
    let mut depth = 0;
    for j in i..stop {
        if depth == 0 && is_ident(&tokens[j]) {
            last = Some(j);
        }
        depth = step_depth(depth, &tokens[j]);
    }
    // `typedef int (*name)(...)`: the name is inside the parentheses.
    let function_pointer = || {
        (i..stop.saturating_sub(3)).find(|&j| {
            tokens[j].text == "("
                && tokens[j + 1].text == "*"
                && is_ident(&tokens[j + 2])
                && tokens[j + 3].text == ")"
        })
    };
    if let Some(name) = last.or_else(|| function_pointer().map(|j| j + 2)) {
        mark(&mut tokens[name], Role::Typedef);
    }
}
