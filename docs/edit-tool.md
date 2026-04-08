# Edit Tool

Инструмент `edit-file` позволяет LLM редактировать файлы через замену текста:
указать что найти (`old-string`) и на что заменить (`new-string`).

## Почему не unified diff

Unified diff требует точного соблюдения формата (`--- a/file`, `+++ b/file`, `@@ -N,N @@`),
и любая ошибка приводит к отказу `patch`. Подход old-string/new-string проще:
модель копирует кусок кода, который хочет заменить, и пишет замену.

## Параметры

| Параметр | Тип | Описание |
|---|---|---|
| `target-file` | string | Путь к файлу (относительный или абсолютный) |
| `instructions` | string | Одно предложение — что делаем |
| `old-string` | string | Текст для поиска; пустая строка — создать файл |
| `new-string` | string | Текст замены |
| `replace-all` | boolean | Заменить все вхождения (по умолчанию false) |

## Создание файла

Если `old-string` пустой — файл создаётся или перезаписывается целиком.
`ensure-directories-exist` создаёт вложенные директории автоматически.

## Каскадные replacer-ы

Когда модель не попадает точно в текст файла (лишние пробелы, другой отступ),
цепочка replacer-ов пробует всё более мягкие варианты совпадения:

| # | Replacer | Что делает |
|---|---|---|
| 1 | `%simple-replacer` | Точное вхождение строки |
| 2 | `%line-trimmed-replacer` | Сравнение строк после `string-trim` (пробелы по краям каждой строки) |
| 3 | `%block-anchor-replacer` | Первая и последняя строки как «якоря», средние — расстояние Левенштейна |
| 4 | `%whitespace-normalized-replacer` | Все пробельные последовательности сворачиваются в один пробел |
| 5 | `%indentation-flexible-replacer` | Из блока вычитается общий минимальный отступ перед сравнением |
| 6 | `%trimmed-boundary-replacer` | Trim всей строки поиска целиком |
| 7 | `%multi-occurrence-replacer` | Только для того, чтобы выдать ошибку «несколько совпадений» |

**Ключевое свойство:** каждый replacer возвращает **подстроку из оригинального файла**
(не из `old-string`). Именно эта подстрока потом ищется в `content` при замене,
поэтому замена попадает ровно в то место, которое нашёл replacer.

## Логика замены (`%replace-in-content`)

```
for replacer in replacers:
  for candidate in replacer(content, old-string):
    first-pos = indexOf(content, candidate)
    if not found: continue           # replacer вернул что-то не из content
    found-any = true
    if replace-all:
      return replaceAll(content, candidate, new-string)
    last-pos = lastIndexOf(content, candidate)
    if first-pos != last-pos: continue  # несколько вхождений — пробуем следующий
    return splice(content, first-pos, len(candidate), new-string)

if found-any: error("multiple matches — add more context or use replace-all")
else:         error("not found")
```

Если совпадение найдено, но не уникально — replacer пропускается и пробуется следующий.
Это даёт шанс более «жёсткому» кандидату оказаться уникальным.

## Работа с переводами строк (CRLF/LF)

1. Определить, что использует файл: `%detect-line-ending`
2. Нормализовать в LF: `%normalize-line-endings`
3. Выполнить замену на нормализованном тексте
4. Вернуть исходные окончания: `%to-crlf` (если файл был CRLF)

Это позволяет не думать о переводах строк внутри replacer-ов — они всегда работают с LF.
