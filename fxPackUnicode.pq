(pathOrUrl as text) as text =>
let
    Address = Text.Trim(pathOrUrl),

    IsUrl =
        Text.StartsWith(Address, "https://", Comparer.OrdinalIgnoreCase)
        or Text.StartsWith(Address, "http://", Comparer.OrdinalIgnoreCase),

    Source =
        if Address = "" then
            error "Укажи путь или прямую ссылку на файл с M-кодом."
        else if IsUrl then
            Web.Contents(Address)
        else
            File.Contents(Address),

    Compressed =
        Binary.Compress(
            Source,
            Compression.Deflate
        ),

    Hex =
        Binary.ToText(
            Compressed,
            BinaryEncoding.Hex
        ),

    Packed =
        fnUnicode15(Hex, false)
in
    Packed
