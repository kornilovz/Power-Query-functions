(s as any) as text =>
    let
        str = if s = null then "" else Text.From(s),
        cleaned = Text.Clean(str),
        trimmed = Text.Trim(cleaned),
        lower = Text.Lower(trimmed),
        deleteSpace = Text.Replace(lower, " ", "")
    in
        deleteSpace