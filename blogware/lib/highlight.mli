val highlight :
  classes:Text.t list -> content:Document.inline list -> Document.inline list
(** [highlight ~classes ~content] applies syntax highlighting to [content] when
    [classes] contains a supported language name.

    The language match is exact. Unsupported classes leave [content] unchanged.
    Non-string inline nodes are preserved, so embedded links, anchors, and
    TeX-derived inline markup remain intact. *)
