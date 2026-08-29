/*
    ФУНКЦИЯ: fnFindHeader
    ЗАДАЧА: найти в "сырой" таблице строку с заголовками столбцов и вернуть
            таблицу с правильными названиями столбцов.

    Зачем это нужно:
    Часто выгрузки из других систем содержат "мусор" перед настоящей таблицей
    (название отчёта, дату выгрузки, пустые строки и т.п.), и реальные заголовки
    столбцов находятся не в первой строке, а где-то ниже. Эта функция сама
    находит нужную строку и "поднимает" её в заголовки.

    ПАРАМЕТРЫ:
        table            - исходная таблица, в которой нужно найти заголовки.
        expectedColumns  - список названий столбцов, которые мы ожидаем увидеть
                           (например: {"ID", "Дата", "Сумма"}).
        minMatches       - (необязательно) сколько столбцов из expectedColumns
                           должно совпасть, чтобы строка считалась заголовком.
                           Если не указано — требуются ВСЕ столбцы из expectedColumns.
        maxRows          - (необязательно) сколько первых строк таблицы просматривать
                           в поисках заголовка. По умолчанию — 30.
        normalizeHeaders - (необязательно) true/false — приводить ли найденные
                           заголовки к единому виду через функцию fnNormalize
                           (убирает лишние пробелы, регистр и т.п.).
                           По умолчанию — true.

    РЕЗУЛЬТАТ:
        Таблица с корректными названиями столбцов и данными, начинающимися
        сразу после найденной строки заголовков.

    ТРЕБОВАНИЯ:
        В той же книге/проекте должна быть определена функция fnNormalize —
        она используется для нормализации текста (названий столбцов и ячеек).

    ЛОГИКА РАБОТЫ (упрощённо):
        1. Проверяем, может быть, заголовки уже стоят на своём месте (текущие
           названия столбцов таблицы совпадают с ожидаемыми) — если да, просто
           переименовываем столбцы и возвращаем таблицу.
        2. Если нет — просматриваем первые maxRows строк таблицы и ищем строку,
           где встречается достаточное количество ожидаемых названий.
        3. Найденную строку делаем заголовком, а всё, что было до и включая neё,
           отбрасываем — остаётся только таблица с данными.

    ВЕРСИЯ: 3.1 — оптимизированная (ускоренная) версия.
    Что изменено по сравнению с предыдущей версией:
        - Функция больше не разбирает всю таблицу на строки и не собирает её
          заново — переименование столбцов происходит "на месте"
          (Table.RenameColumns). Это значительно быстрее на больших таблицах
          и, если данные приходят из базы данных, позволяет части работы
          выполниться на стороне источника, а не в Power Query.
        - Добавлена защита от повторяющихся названий столбцов после
          нормализации (см. функцию dedupNames ниже).
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
            // Функция нормализации текста — определена отдельно в проекте
            normalize = fnNormalize,

            // -----------------------------------------------------------
            // Блок 1. Вспомогательные функции
            // -----------------------------------------------------------

            // Если после нормализации несколько столбцов получили одинаковое
            // название (например, "Итог" и "итог "), делаем их уникальными:
            // второе повторение получит имя "Итог_1", третье — "Итог_2" и т.д.
            // Это нужно, потому что Power Query не разрешает таблице иметь
            // два столбца с одинаковым именем.
            dedupNames = (names as list) as list =>
                List.Accumulate(
                    names,
                    [alreadyUsed = {}, uniqueNames = {}],
                    (state, currentName) =>
                        let
                            howManyTimesSeen = List.Count(List.Select(state[alreadyUsed], each _ = currentName)),
                            uniqueName = if howManyTimesSeen = 0 then currentName else currentName & "_" & Text.From(howManyTimesSeen)
                        in
                            [
                                alreadyUsed = state[alreadyUsed] & {currentName},
                                uniqueNames = state[uniqueNames] & {uniqueName}
                            ]
                )[uniqueNames],

            // Проверяет, есть ли искомое слово (pattern) хотя бы в одной ячейке строки
            rowContainsPattern = (rowValues as list, pattern as text) as logical =>
                List.AnyTrue(List.Transform(rowValues, each Text.Contains(_, pattern))),

            // Проверяет, содержит ли строка достаточное количество ожидаемых столбцов
            isHeaderRow = (rowValues as list, patternsList as list, requiredCount as number) as logical =>
                let
                    normalizedRow = List.Buffer(List.Transform(rowValues, each if _ = null then "" else normalize(_))),
                    foundCount = List.Count(List.Select(patternsList, each rowContainsPattern(normalizedRow, _)))
                in
                    foundCount >= requiredCount,

            // -----------------------------------------------------------
            // Блок 2. Подготовка параметров и данных
            // -----------------------------------------------------------

            // Сколько совпадений считаем достаточным (по умолчанию — все ожидаемые столбцы)
            requiredMatches = if minMatches = null then List.Count(expectedColumns) else minMatches,

            // Сколько строк просматривать в поиске заголовка (по умолчанию 30)
            rowsToScan = if maxRows = null then 30 else maxRows,

            // Нужно ли нормализовать итоговые названия столбцов (по умолчанию — да)
            shouldNormalize = if normalizeHeaders = null then true else normalizeHeaders,

            // Ожидаемые названия столбцов, приведённые к единому виду для сравнения
            expectedPatterns = List.Buffer(List.Transform(expectedColumns, each normalize(_))),

            // Убираем возможные ошибки в ячейках таблицы, заменяя их на пустое значение,
            // чтобы дальнейшая обработка не прерывалась из-за некорректных данных
            cleanTable = Table.ReplaceErrorValues(table, List.Transform(Table.ColumnNames(table), each {_, null})),

            currentColumnNames = Table.ColumnNames(cleanTable),
            normalizedCurrentNames = List.Transform(currentColumnNames, each normalize(_)),

            // -----------------------------------------------------------
            // Блок 3. Проверка — может быть, заголовки уже на месте?
            // -----------------------------------------------------------
            matchesInCurrentNames = List.Count(List.Select(expectedPatterns, each rowContainsPattern(normalizedCurrentNames, _))),
            headersAlreadyCorrect = matchesInCurrentNames >= requiredMatches,

            // -----------------------------------------------------------
            // Блок 4. Итоговый результат
            // -----------------------------------------------------------
            finalResult =
                if headersAlreadyCorrect then
                    // Случай А: текущие названия столбцов уже подходят —
                    // просто переименовываем их (без изменения самих данных)
                    let
                        newColumnNames = dedupNames(
                            if shouldNormalize then List.Transform(currentColumnNames, each normalize(_)) else currentColumnNames
                        ),
                        renamedTable = Table.RenameColumns(cleanTable, List.Zip({currentColumnNames, newColumnNames}), MissingField.Ignore)
                    in
                        renamedTable
                else
                    // Случай Б: нужно найти строку-заголовок среди первых rowsToScan строк
                    let
                        rowsSample = List.Buffer(Table.ToRows(Table.FirstN(cleanTable, rowsToScan))),
                        rowIndexes = List.Positions(rowsSample),

                        // Индекс первой строки, которая похожа на заголовок
                        headerRowIndex = List.First(
                            List.Select(rowIndexes, each isHeaderRow(rowsSample{_}, expectedPatterns, requiredMatches)),
                            null
                        ),

                        headerRowValues =
                            if headerRowIndex = null then
                                error "Не удалось найти строку с заголовками. Проверьте expectedColumns или увеличьте maxRows."
                            else
                                rowsSample{headerRowIndex},

                        newColumnNames = dedupNames(
                            if shouldNormalize then
                                List.Transform(headerRowValues, each normalize(_))
                            else
                                List.Transform(headerRowValues, each if _ = null then "" else Text.From(_))
                        ),

                        // Данные — это всё, что идёт после найденной строки заголовка
                        dataOnly = Table.Skip(cleanTable, headerRowIndex + 1),
                        renamedTable = Table.RenameColumns(dataOnly, List.Zip({currentColumnNames, newColumnNames}), MissingField.Ignore)
                    in
                        renamedTable
        in
            finalResult
in
    Источник