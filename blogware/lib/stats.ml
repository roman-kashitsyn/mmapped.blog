open Document

let is_ascii_alnum c =
  match c with '0' .. '9' | 'A' .. 'Z' | 'a' .. 'z' -> true | _ -> false

let is_word_byte c = is_ascii_alnum c || Char.code c >= 0x80

type count_state = { words : int; in_word : bool }
type scan_mode = Idle | InWord | AfterConnector

let break_word state = { state with in_word = false }

let count_words_in_text (state : count_state) (s : Text.t) : count_state =
  let mode = ref (if state.in_word then InWord else Idle) in
  let words = ref state.words in
  let f c =
    match !mode with
    | Idle ->
        if is_word_byte c then (
          incr words;
          mode := InWord)
    | InWord ->
        if is_word_byte c then ()
        else if c = '\'' || c = '-' then mode := AfterConnector
        else mode := Idle
    | AfterConnector -> if is_word_byte c then mode := InWord else mode := Idle
  in
  Text.iter f s;
  { words = !words; in_word = !mode = InWord }

let count_inlines (ils : inline list) : int =
  let rec go state = function
    | [] -> state
    | il :: rest ->
        let state = count_inline state il in
        go state rest
  and count_inline state = function
    | Str t -> count_words_in_text state t
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
