# Lessons Learned

Документация по логике edit tool: [docs/edit-tool.md](docs/edit-tool.md)

## Строковые литералы в Common Lisp

**`"\n"` в CL — это NOT перевод строки, а backslash + `n`.**

Правильные способы написать перевод строки:
```lisp
(string #\Newline)           ; символьная константа
(format nil "line1~%line2")  ; через ~%
```

В тестах это особенно важно: `"a\nb"` ≠ `"a" + #\Newline + "b"`. Из-за этого тесты с `"\n"` могут проходить по неправильной причине (обе стороны сравнения одинаково «неправильные»).

## ASDF package-inferred systems и log4cl

Если файл использует пакет `LOG` через `log:info` без `:import-from`, ASDF не знает, что надо загрузить `log4cl`, и компиляция падает с «Package LOG does not exist».

Решение: добавить явный импорт в `uiop:define-package`:
```lisp
(:import-from #:log #:info)
```
Это позволяет ASDF inference найти зависимость через `(asdf:register-system-packages "log4cl" '("LOG"))` в основном `.asd`.

Использовать импортированный символ напрямую:
```lisp
(info "message" ...)   ; вместо (log:info "message" ...)
```

## Rove: синтаксис `signals`

```lisp
;; ПРАВИЛЬНО — тело как первый аргумент:
(signals (some-expression-that-should-signal))
(signals (some-expression) 'my-error-type)

;; НЕПРАВИЛЬНО:
(signals (error)
  (some-expression))
```

## Рабочий процесс: отметка выполненных пунктов плана

После реализации фичи из плана — добавить `✓` к заголовку соответствующего пункта в `docs/implementation-plan.md`:

```
### 1.1 Bash Tool ✓
```

## Тестирование internal функций

Чтобы тестировать `%private-fn` из другого пакета, нужно:
1. Явно экспортировать из исходного пакета: `(:export #:%private-fn)`
2. Импортировать в тестовый пакет: `(:import-from #:my-package #:%private-fn)`

Это нормально для тестов — знак `%` уже сигнализирует «внутренний».
