(Data as table) =>
    let
        colNames = Table.ColumnNames(Data),
        keys = Record.FieldNames(TableRename),
        pairs = List.Accumulate(
            keys,
            {},
            (state, key) =>
                let
                    oldNames = Record.Field(TableRename, key),
                    pos = List.PositionOfAny(oldNames, colNames, Occurrence.First)
                in
                    if pos = -1 then
                        state
                    else
                        List.Combine({state, {{oldNames{pos}, key}}})
        ),
        rename = Table.RenameColumns(Data, pairs, MissingField.Ignore),
        // Преобразуем pairs в запись: ключи = новые имена, значения = старые имена
        foundRecord = Record.FromList(
            List.Transform(pairs, each _{0}),
            List.Transform(pairs, each _{1})
        )
    in
        [RenamedTable = rename, FoundRecord = foundRecord]
