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

## Использовать log:info вместо format для вывода

Для вывода сообщений использовать `log:info` вместо `(format t ...)`. Это даёт структурированный вывод, уровни логирования и возможность перенаправить/отключить вывод без правки кода.

```lisp
;; ПРАВИЛЬНО — полностью квалифицированный символ:
(log:info "tokens: ~A in / ~A out | cost: $~,3F" turn-in turn-out turn-cost)

;; НЕПРАВИЛЬНО — format:
(format t "~&[tokens: ~A in / ~A out | cost: $~,3F]~%" turn-in turn-out turn-cost)

;; НЕПРАВИЛЬНО — импортировать символ из LOG:
(:import-from #:log #:info)
(info "...")
```

Писать `log:info` напрямую, без импорта. Зависимость на `log4cl` уже зарегистрирована в `codabrus.asd` через `asdf:register-system-packages`.

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

## Использовать CLOS, не defstruct

В этом проекте все типы данных определяются через `defclass`, не `defstruct`.

### Конструктор для defclass

Для каждого `defclass` нужна функция-конструктор `make-<classname>`.

- Обязательные слоты → обязательные позиционные параметры.
- Необязательные слоты → `&key` параметры, но объявленные через `&rest restargs` и переданные в `make-instance` через `apply`. Тогда не нужно указывать дефолтные значения — их задаёт сам `defclass`.
- В сигнатуре всё равно перечислять все допустимые `&key`, затем `(declare (ignore ...))` на каждый из них — для документации и проверки компилятором.

```lisp
(defclass session ()
  ((project-dir :initarg :project-dir
                :reader   session-project-dir)
   (state       :initarg  :state
                :initform nil
                :accessor session-state)))

(defun make-session (project-dir &rest restargs &key state)
  (declare (ignore state))
  (apply #'make-instance 'session :project-dir project-dir restargs))
```

Почему `&rest` + `apply`, а не просто передать `state` явно:
- Не нужно дублировать дефолт из `defclass` в конструкторе.
- Если слот не передан — `make-instance` использует `:initform`; если передан — используется переданное значение.
- При добавлении нового необязательного слота достаточно добавить его в `&key` список и `declare ignore`, не трогая тело функции.

```lisp
;; ПРАВИЛЬНО:
(defclass session ()
  ((project-dir :initarg :project-dir :reader session-project-dir)
   (state       :initarg :state       :accessor session-state)))

(make-instance 'session :project-dir #p"/tmp/" :state nil)

;; НЕПРАВИЛЬНО:
(defstruct session project-dir state)
```

Причина: `defclass` лучше совместим с CLOS (методы, наследование, MOP), что важно для будущего расширения агентов.

При переопределении `defstruct` → `defclass` в живом образе необходимо удалить пакет перед перезагрузкой:
```lisp
(delete-package :my-package)
(asdf:load-system "my-system" :force '("my-system/my-file"))
```

## Вычисление Lisp-форм через MCP

Вместо запуска `sbcl` через `Bash`, использовать инструмент `mcp__lisp-dev-mcp__eval_lisp_form`:

```lisp
;; Пример: узнать версию реализации
(lisp-implementation-type)    ; => "SBCL"
(lisp-implementation-version) ; => "2.6.0.roswell"
```

Это предпочтительный способ — не требует подтверждения пользователя и выполняется в живом REPL-сессии.
