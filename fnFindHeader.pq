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
          
    Изменения в версии 2.0:
        - Оптимизирована логика нормализации параметров (вынесена дублирующаяся переменная needNorm)
        - Устранены лишние преобразования Table.ToRows() (был дважды в headersOk ветке)
        - Улучшена функция listContains с использованием ленивого вычисления (List.Generate)
        - Добавлено буферизирование промежуточных списков для лучшей производительности
        - Удален мертвый код и улучшена читаемость
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
            // ✅ ОПТИМИЗАЦИЯ: Ленивое вычисление с ранним выходом при первом совпадении
            // Проверяет, содержит ли хотя бы один элемент списка lst подстроку pat
            listContains = (lst as list, pat as text) as logical =>
                let
                    count = List.Count(lst),
                    gen = List.Generate(
                        () => [i = 0, found = false],
                        each [i] < count,
                        // условие всегда true для всех допустимых индексов
                        each
                            let
                                current_found = Text.Contains(lst{[i]}, pat),
                                // Если уже нашли на предыдущем шаге — переходим на позицию count, чтобы завершить цикл
                                next_i = if [found] then count else (if current_found then [i] else [i] + 1),
                                next_found = [found] or current_found
                            in
                                [i = next_i, found = next_found],
                        each [found]
                    )
                in
                    List.AnyTrue(gen),
            // Проверяет, удовлетворяет ли строка row условию: содержит минимум required совпадений с patterns
            rowMatches = (row as list, patterns as list, required as number) as logical =>
                let
                    // Нормализуем все элементы строки (заменяем null на пустую строку)
                    // ✅ ОПТИМИЗАЦИЯ: буферизируем для лучшей производительности при множественном доступе
                    rowNorm = List.Buffer(List.Transform(row, each if _ = null then "" else normalize(_))),
                    // Для каждого шаблона проверяем, содержится ли он в любой ячейке строки
                    matches = List.Transform(patterns, (pat) => listContains(rowNorm, pat)),
                    // Считаем количество истинных совпадений
                    count = List.Count(List.Select(matches, each _ = true))
                in
                    count >= required,
            // ✅ ОПТИМИЗАЦИЯ: Вынесли нормализацию параметров один раз (раньше дублировалась)
            // Определяем минимальное количество совпадений, необходимое для признания строки заголовком
            required = if minMatches = null then List.Count(expectedColumns) else minMatches,
            // Ограничение на количество анализируемых строк при поиске
            limit = if maxRows = null then 30 else maxRows,
            // Флаг нормализации заголовков (используется в обеих ветках)
            needNorm = if normalizeHeaders = null then true else normalizeHeaders,
            // Буферизируем нормализованные шаблоны для повышения производительности
            patterns = List.Buffer(List.Transform(expectedColumns, each normalize(_))),
            // Заменяем все ошибки в таблице на null, чтобы избежать сбоев при преобразованиях
            cleaned = Table.ReplaceErrorValues(table, List.Transform(Table.ColumnNames(table), each {_, null})),
            // Получаем текущие имена столбцов
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
                        // Итоговая строка заголовков (либо нормализованная, либо исходная)
                        finalHeaderRow =
                            if needNorm then
                                List.Transform(oldHeaderRow, each normalize(_))
                            else
                                oldHeaderRow,
                        // ✅ ОПТИМИЗАЦИЯ: Одно преобразование Table.ToRows вместо двух
                        allRows = Table.ToRows(cleaned)
                    in
                        buildTable(finalHeaderRow, allRows)
                else
                    // Если текущие заголовки не подходят, ищем строку-заголовок среди первых limit строк
                    let
                        // Берём первые limit строк для анализа
                        smallTable = Table.FirstN(cleaned, limit),
                        // Преобразуем их в список списков и буферизируем
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
                        // Нормализуем заголовки (приводим к тексту, заменяем null)
                        finalHeaderRow =
                            if needNorm then
                                List.Transform(rawHeaderRow, each normalize(_))
                            else
                                List.Transform(rawHeaderRow, each if _ = null then "" else Text.From(_)),
                        // Данные начинаются со следующей строки после найденного заголовка
                        dataRows = Table.ToRows(Table.Skip(cleaned, headerIndex + 1))
                    in
                        buildTable(finalHeaderRow, dataRows)
        in
            result
in
    Источник
