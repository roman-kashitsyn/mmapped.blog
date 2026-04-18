open Document

let is_ascii_alnum c =
  match c with '0' .. '9' | 'A' .. 'Z' | 'a' .. 'z' -> true | _ -> false

let is_word_byte c = is_ascii_alnum c || Char.code c >= 0x80

type count_state = { words : int; in_word : bool }

let break_word state = { state with in_word = false }

let count_words_in_string (state : count_state) (s : string) : count_state =
  let len = String.length s in
  let rec loop i state =
    if i >= len then state
    else
      let c = s.[i] in
      if is_word_byte c then
        let words = if state.in_word then state.words else state.words + 1 in
        loop (i + 1) { words; in_word = true }
      else
        match c with
        | ('\'' | '-') when state.in_word ->
            let continues = i + 1 < len && is_word_byte s.[i + 1] in
            loop (i + 1) { state with in_word = continues }
        | _ -> loop (i + 1) { state with in_word = false }
  in
  loop 0 state

let count_inlines (ils : inline list) : int =
  let rec go state = function
    | [] -> state
    | il :: rest ->
        let state = count_inline state il in
        go state rest
  and count_inline state = function
    | Str s -> count_words_in_string state s
    | Strong ils
    | Emph ils
    | Underline ils
    | Small_caps ils
    | Strikethrough ils
    | Kbd ils
    | Sub ils
    | Sup ils
    | Quotation ils
    | Fun ils
    | Math_span ils
    | Normal ils
    | Link (_, ils)
    | Margin_note (_, ils)
    | Side_note (_, ils) ->
        go state ils
    | Code _ | Math _ | Horizontal_rule | Circled_ref _ | Line_break
    | Numeric_space | Nameref _ | Image_inline _ ->
        break_word state
    | Anchor _ -> state
  in
  let state = go { words = 0; in_word = false } ils in
  state.words

let rec count_block (b : block) : int =
  match b with
  | Para ils | Plain ils -> count_inlines ils
  | Section (header, body) ->
      let header_count =
        match header with None -> 0 | Some (_, title) -> count_inlines title
      in
      header_count + count_blocks body
  | Subsection (_, title, body) -> count_inlines title + count_blocks body
  | Code_block _ | Verbatim_block _ | Image _ | HRule -> 0
  | Bullet_list (_, items) | Ordered_list items ->
      List.fold_left (fun acc blocks -> acc + count_blocks blocks) 0 items
  | Description_list items ->
      List.fold_left
        (fun acc (term, def_) -> acc + count_inlines term + count_blocks def_)
        0 items
  | Blockquote (body, attribution) | Epigraph (body, attribution) ->
      count_blocks body + count_inlines attribution
  | Table td ->
      let count_cell cell = count_inlines cell.tc_content in
      let count_row row =
        List.fold_left (fun acc cell -> acc + count_cell cell) 0 row.tr_cells
      in
      let header_count =
        match td.table_header with None -> 0 | Some row -> count_row row
      in
      header_count
      + List.fold_left (fun acc row -> acc + count_row row) 0 td.table_rows
  | Figure (_, body) | Abstract body | Center body -> count_blocks body
  | Advice (_, ils) -> count_inlines ils
  | Details (summary, body) -> count_inlines summary + count_blocks body

and count_blocks (blocks : block list) : int =
  List.fold_left (fun acc block -> acc + count_block block) 0 blocks

let word_count (doc : block list) : int = count_blocks doc
