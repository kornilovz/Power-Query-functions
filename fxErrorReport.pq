let
    fxОтчётОбОшибках = (
        tbl as table, 
        optional keyCols as list, 
        optional scanCols as list
    ) as record =>
    let
        allCols = Table.ColumnNames(tbl),
        validKeys = List.Intersect({allCols, keyCols ?? {}}),
        hasKeys = List.Count(validKeys) > 0,
        validScans = List.Intersect({allCols, scanCols ?? {}}),
        // берём нужные столбцы
        subTbl = Table.SelectColumns(tbl, if List.Count(validScans) > 0 then validKeys & validScans else allCols),
        // зарезервированные имена (на русском)
        reserved = {"Имя", "Ошибки", "Причина", "Сообщение", "Подробно", "НомерСтроки", "внутр"},
        conflict = List.Intersect({allCols, reserved}),
        // основной блок
        result = if List.IsEmpty(conflict) then
            let
                src = if hasKeys 
                      then Table.SelectRowsWithErrors(subTbl)
                      else Table.SelectRowsWithErrors(Table.AddIndexColumn(subTbl, "НомерСтроки", 0, 1, Int64.Type)),
                // преобразуем каждую строку: находим поля с ошибками
                step = Table.SelectColumns(
                    Table.AddColumn(src, "внутр", each 
                        let 
                            rec = Record.ToTable(_),
                            errRows = Table.SelectRowsWithErrors(rec, {"Value"}),
                            withErr = Table.AddColumn(errRows, "Ошибки", each 
                                let tryVal = try [Value] in if tryVal[HasError] then tryVal[Error] else null
                            )
                        in 
                            withErr[[Name], [Ошибки]]
                    ),
                    if hasKeys then validKeys & {"внутр"} else {"НомерСтроки", "внутр"}
                ),
                // разворачиваем вложенные таблицы и записи ошибок
                out = Table.ExpandRecordColumn(
                    Table.ExpandTableColumn(step, "внутр", {"Name", "Ошибки"}),
                    "Ошибки", {"Reason", "Message", "Detail"}
                )
            in out
            else error "Переименуйте столбцы: " & Text.Combine(conflict, ", "),
        // итоговая запись
        output = [
            Количество_ошибок = Table.RowCount(result),
            Данные = result,
            Неверные_ключи = List.Difference(keyCols ?? {}, validKeys),
            Неверные_сканы = List.Difference(scanCols ?? {}, validScans)
        ]
    in output,

    // документация — ВСЁ В ОДНУ СТРОКУ (без переносов)
    doc = [
        Documentation.Name = "Отчёт об ошибках в таблице",
        Documentation.Description = "Возвращает запись с полями: Количество_ошибок, Данные (таблица с ошибками по столбцам), Неверные_ключи и Неверные_сканы. Если ключевые столбцы не заданы, добавляет НомерСтроки. Проверяет только указанные scanCols, иначе все столбцы. Нельзя использовать имена: Имя, Ошибки, Причина, Сообщение, Подробно, НомерСтроки, внутр.",
        Documentation.Author = "Melissa de Korte (адаптация, русский)",
        Documentation.Version = "1.0"
    ]
in
    Value.ReplaceType(fxОтчётОбОшибках, Value.ReplaceMetadata(Value.Type(fxОтчётОбОшибках), doc))