(path as text) as function =>
    let
        source = Expression.Evaluate(Text.FromBinary(File.Contents(path)), #shared)
    in
        source
