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

## Где найти исходники Lisp-библиотеки

Чтобы узнать путь к исходникам установленной библиотеки, использовать:

```lisp
(ql:where-is-system :defmain)
; => #p"/Users/art/.roswell/lisp/quicklisp/dists/quicklisp/software/defmain-..."
```

Вызывать через MCP-инструмент `mcp__lisp-dev-mcp__eval_lisp_form`.

## Правила изменения локальных библиотек

### libs/ai-agents (40ants-ai-agents)

Локальная fork — **можно менять без сохранения обратной совместимости**. Это наша библиотека, используемая только codabrus. Каждое значимое изменение кратко описывать в `libs/ai-agents/docs/changelog.lisp`.

### libs/completions

**Сторонняя библиотека** (оригинал — Anthony Green). Менять только после явного подтверждения от Art. Все изменения проектировать так, чтобы их можно было отправить в upstream:
- Минимальные, целенаправленные патчи
- Без breaking changes в существующем API
- Новые фичи добавлять через необязательные переменные/параметры (как `*tool-events*`)

## Как избежать проблем со скобками в Lisp

При написании новых `.lisp`-файлов (особенно длинных, 100+ строк) часто возникают ошибки несогласованных скобок. Паттерны ошибок и решения:

### 1. Не писать большие файлы целиком

Разбивать большие функции на вспомогательные (helper) функции. В этой сессии `openai-completions-loop` (одна функция на 100 строк с 10 уровнями вложенности) была источником большинства ошибок. После разбиения на `openai-streaming-loop`, `openai-non-streaming-loop`, `exec-tool-calls`, `build-payload` каждая функция стала короче и проще.

### 2. Проверять скобки перед компиляцией

Использовать скрипт проверки глубины скобок **до** `asdf:load-system`:

```lisp
(let* ((content (uiop:read-file-string "path/to/file.lisp"))
       (lines (cl-ppcre:split "\\n" content))
       (depth 0))
  (loop for line in lines
        for i from 1
        for d = (let ((dd 0) (in-str nil) (in-com nil))
                  (loop for ch across line
                        do (cond (in-com)
                                 (in-str (when (char= ch #\") (setf in-str nil)))
                                 ((char= ch #\;) (setf in-com t))
                                 ((char= ch #\") (setf in-str t))
                                 ((char= ch #\() (incf dd) (incf depth))
                                 ((char= ch #\)) (decf dd) (decf depth))))
                  dd)
        when (< depth 0)
          do (format t "*** NEGATIVE at line ~A~%" i))
  (format t "Final depth: ~A~%" depth))
```

Если `Final depth` ≠ 0 — файл содержит ошибку. ЕслиNegative depth — лишняя `)` на указанной строке.

### 3. Осторожнее с `))))` — считать уровни

Самая частая ошибка: закрывающих скобок на 1 больше или меньше нужного. Правило: перед `))))` проговорить вслух что именно закрывается. Пример опасного места:

```lisp
;; 7 уровней закрывающих — легко ошибиться:
                                                    args)))))))
;; Лучше — вынести во вспомогательную переменную/функцию
```

### 4. JSON внутри ai-agents — использовать utils.lisp

Внутри `libs/ai-agents/` **всегда** использовать `40ants-ai-agents/utils:json-encode` и `40ants-ai-agents/utils:json-parse` вместо прямых вызовов YASON или локальных `%json-encode`/`%json-parse`.

**Не использовать alists для JSON-данных.** Все JSON-объекты — hash-tables со строковыми ключами. Создавать через `serapeum:dict`, не `make-hash-table`. Никаких `:object-as :alist`, `*list-encoder*`, `*symbol-key-encoder*`, `*symbol-encoder*` — это всё лишнее.

```lisp
;; ПРАВИЛЬНО:
(serapeum:dict "a" 1 "b" (serapeum:dict "nested" 42))
;; => #<HASH-TABLE "a" → 1, "b" → {"nested" → 42}>

;; НЕПРАВИЛЬНО:
'((:a . 1) (:b . 2))  ;; alists для JSON-данных
```

Флаги YASON для round-trip: `:json-arrays-as-vectors t`, `:json-booleans-as-symbols t`, `:json-nulls-as-keyword t`. Без последнего и `nil`, и `[]` превращаются в пустой JSON-массив.

**`yason:with-output-to-string*` не передавайте nil в encode.** Макрос устанавливает выходной поток, но его нужно использовать без явного stream-аргумента:

```lisp
;; ПРАВИЛЬНО:
(yason:with-output-to-string* ()
  (yason:encode object))

;; НЕПРАВИЛЬНО — nil подавляет вывод, возвращает пустую строку:
(yason:with-output-to-string* ()
  (yason:encode object nil))
```

Провайдеры (`openai.lisp`, будущие `anthropic.lisp` и т.д.) должны `:import-from #:40ants-ai-agents/utils #:json-encode #:json-parse`. Сейчас в `openai.lisp` и `llm-provider.lisp` ещё остались локальные `%json-encode`/`%json-parse` — их нужно заменить на импорт из utils.
