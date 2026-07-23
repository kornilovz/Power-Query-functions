// Докстринг: описание функции, её параметров и возвращаемого значения
/*
    Функция для интеллектуального поиска и извлечения таблицы с заголовками из "сырых" данных.
    Она анализирует входную таблицу, ищет строку, которая с наибольшей вероятностью является заголовком,
    и возвращает таблицу с правильными именами столбцов.

    Параметры:
        table           - таблица (тип table), в которой нужно найти заголовки.
        expectedColumns - список ожидаемых имён столбцов (list of text).
        minMatches      (необязательный) - минимальное количество совпадений с expectedColumns,
                           чтобы считать строку заголовком. По умолчанию = количество expectedColumns.
        maxRows         (необязательный) - сколько первых строк таблицы анализировать при поиске.
                           По умолчанию = 30.
        normalizeHeaders (необязательный) - логический флаг: нужно ли нормализовать (приводить к общему виду)
                           имена столбцов с помощью внешней функции fnNormalize.
                           По умолчанию = true.

    Возвращает:
        Таблицу (table) с корректными заголовками.

    Примечания:
        - Для нормализации строк используется внешняя функция fnNormalize (должна быть определена заранее).
        - Для переименования столбцов после построения применяется внешняя функция fnRenameColumns.
        - Если заголовки найдены в первых строках, они используются "как есть" или нормализуются.
        - Если заголовки не найдены в текущих именах столбцов, функция сканирует первые maxRows строк
          в поисках строки, удовлетворяющей условию совпадений.
*/
let
    Источник = (
    table as table,
    expectedColumns as list,
    optional minMatches as number,
    optional maxRows as number,
    optional normalizeHeaders as logical
) =>
    let
        // Вспомогательная функция для нормализации строк (внешняя)
        normalize = fnNormalize,
        // Вспомогательная функция для построения таблицы из строки заголовков и строк данных
        buildTable = (headerRow as list, dataRows as list) as table =>
            let
                // Объединяем заголовок и данные в один список строк
                newRows = {headerRow} & dataRows,
                // Создаём временную таблицу из списка списков
                tempTable = Table.FromRows(newRows),
                // Продвигаем первую строку в заголовки (PromoteAllScalars = true преобразует все значения к скалярам)
                promoted = Table.PromoteHeaders(tempTable, [PromoteAllScalars = true])
            in
                promoted,
        // Проверяет, содержит ли хотя бы один элемент списка lst подстроку pat (регистронезависимо?)
        // Здесь используется Text.Contains, которая по умолчанию чувствительна к регистру,
        // но т.к. мы нормализуем строки, это не критично.
        listContains = (lst as list, pat as text) as logical =>
            List.AnyTrue(List.Transform(lst, each Text.Contains(_, pat))),
        // Проверяет, удовлетворяет ли строка row условию: содержит минимум required совпадений с patterns
        rowMatches = (row as list, patterns as list, required as number) as logical =>
            let
                // Нормализуем все элементы строки (заменяем null на пустую строку)
                rowNorm = List.Transform(row, each if _ = null then "" else normalize(_)),
                // Для каждого шаблона проверяем, содержится ли он в любой ячейке строки
                matches = List.Transform(patterns, (pat) => listContains(rowNorm, pat)),
                // Считаем количество истинных совпадений
                count = List.Count(List.Select(matches, each _ = true))
            in
                count >= required,
        // Определяем минимальное количество совпадений, необходимое для признания строки заголовком
        required = if minMatches = null then List.Count(expectedColumns) else minMatches,
        // Ограничение на количество анализируемых строк при поиске
        limit = if maxRows = null then 30 else maxRows,
        // Буферизируем нормализованные шаблоны для повышения производительности
        patterns = List.Buffer(List.Transform(expectedColumns, each normalize(_))),
        // Заменяем все ошибки в таблице на null, чтобы избежать сбоев при преобразованиях
        cleaned = Table.ReplaceErrorValues(table, List.Transform(Table.ColumnNames(table), each {_, null})),
        // Получаем текущие имена столбцов (они же первая строка данных, если заголовки не были продвинуты)
        currentCols = Table.ColumnNames(cleaned),
        // Нормализуем текущие имена столбцов
        normCurrent = List.Transform(currentCols, each normalize(_)),
        // Считаем, сколько шаблонов содержится в текущих именах столбцов
        colMatches = List.Count(List.Select(patterns, (pat) => listContains(normCurrent, pat))),
        // Проверяем, достаточно ли совпадений среди текущих заголовков
        headersOk = colMatches >= required,
        // Основной результат
        result =
            if headersOk then
                // Если текущие заголовки подходят, используем их
                let
                    // Старые имена столбцов (предположительно уже корректные)
                    oldHeaderRow = Table.ColumnNames(cleaned),
                    // Определяем, нужно ли нормализовать заголовки (по умолчанию true)
                    needNorm = if normalizeHeaders = null then true else normalizeHeaders,
                    // Итоговая строка заголовков (либо нормализованная, либо исходная)
                    finalHeaderRow = if needNorm then List.Transform(oldHeaderRow, each normalize(_)) else oldHeaderRow,
                    // Данные - все строки таблицы (без пропуска, т.к. заголовки уже в именах столбцов)
                    dataRows = Table.ToRows(Table.Skip(cleaned, 0))
                in
                    // Строим таблицу с заголовками и данными
                    let
                        allRows = Table.ToRows(cleaned),
                        // все строки, включая потенциальные старые заголовки?
                        resultTable = buildTable(finalHeaderRow, allRows)
                    in
                        resultTable
            else
                // Если текущие заголовки не подходят, ищем строку-заголовок среди первых limit строк
                let
                    // Берём первые limit строк для анализа
                    smallTable = Table.FirstN(cleaned, limit),
                    // Преобразуем их в список списков
                    rowsToCheck = List.Buffer(Table.ToRows(smallTable)),
                    // Индексы строк
                    indices = List.Positions(rowsToCheck),
                    // Находим первый индекс, где строка удовлетворяет условиям
                    headerIndex = List.First(
                        List.Select(indices, each rowMatches(rowsToCheck{_}, patterns, required)), null
                    ),
                    // Если индекс не найден, генерируем ошибку
                    rawHeaderRow =
                        if headerIndex = null then
                            error "Заголовки не найдены"
                        else
                            // Берём строку-заголовок из исходной таблицы (не из smallTable, чтобы не потерять данные)
                            Table.ToRows(Table.Skip(cleaned, headerIndex)){0},
                    // Флаг нормализации
                    needNorm = if normalizeHeaders = null then true else normalizeHeaders,
                    // Нормализуем заголовки (приводим к тексту, заменяем null)
                    finalHeaderRow =
                        if needNorm then
                            List.Transform(rawHeaderRow, each normalize(_))
                        else
                            List.Transform(rawHeaderRow, each if _ = null then "" else Text.From(_)),
                    // Данные начинаются со следующей строки после найденного заголовка
                    dataRows = Table.ToRows(Table.Skip(cleaned, headerIndex + 1)),
                    // Строим итоговую таблицу
                    resultTable = buildTable(finalHeaderRow, dataRows)
                in
                    resultTable
        // После построения таблицы применяем внешнюю функцию переименования столбцов (например, для очистки)
    in
        result 
in
    Источник
