# Тестовые хосты: установка и проверка

Когда на основном ПК остаётся меньше 6144 MB свободной RAM, `build_shell/test/linux_test.sh` сам переносит
сборку и запуск игры на другой компьютер локальной сети — тестовый хост. Как это работает, описано в разделе
`Test hosts` файла `md/shared/PARALLEL_TEST_INSTANCES.md`. Здесь — только установка.

Адреса нигде настраивать не нужно: основной ПК находит хосты широковещанием (UDP 47800), так что смена IP
ничего не ломает. Хост принимает запросы только из локальной сети.

Поддерживаются Linux (Ubuntu 22.04+) и macOS. Windows пока не поддерживается.

## 1. Основной ПК: раздать установщик

```bash
python3 build_shell/test/test_host.py share
```

Команда печатает по одной строке установки для Linux и для Mac и раздаёт по сети файл `test_host.py`, пока не
нажат Ctrl+C. В строках стоит текущий IP основного ПК: он нужен только для скачивания файла в момент установки,
дальше хосты находятся широковещанием, и смена IP ничего не ломает.

## 2. Тестовый хост: вставить одну строку

### Linux

Открой терминал на рабочем столе (не по ssh) и вставь строку `Run on a Linux test host` из шага 1. Она:
- ставит git, Python, JDK 25, Xvfb и VirtualGL;
- включает запуск пользовательских сервисов без входа в систему;
- скачивает `test_host.py` в `~/test_host.py`;
- устанавливает агент с автозапуском и сразу выводит проверку.

### Mac

1. Один раз нужен Homebrew. Если его нет:

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

   В конце установщик Homebrew пишет «Next steps» с двумя командами `echo ... >> ~/.zprofile` и `eval ...` —
   выполни их и открой новое окно терминала.
2. Вставь строку `Run on a Mac test host` из шага 1. Она:
   - ставит bash 5, JDK 25 (`openjdk`), Python и git;
   - отключает сон при питании от сети;
   - скачивает и устанавливает агент, затем выводит проверку.

   Пароль спросят для `sudo`. Если macOS спросит «Разрешить Python принимать входящие подключения?», нажми
   «Разрешить».

После установки агент запускается сам после каждого входа в систему. Больше ничего запускать не нужно.

## 3. Тестовый хост: проверка

Установка сама печатает проверку. Повторить её можно в любой момент:

```bash
python3 ~/test_host.py check
```

На Mac — `"$(brew --prefix)/bin/python3" ~/test_host.py check`.

Каждая строка помечена `OK` или `FAIL`. Последняя строка должна быть `READY: this computer can take test builds`.

| Строка | Что должно быть |
| --- | --- |
| `host` | имя компьютера, `Linux x86_64` или `Darwin arm64` / `Darwin x86_64` |
| `free RAM` | не меньше 6144 MB свободно. Если меньше, хост виден, но сборки на него не уходят |
| `python` | 3.9 или новее |
| `git` | любая версия |
| `java` | 25 или новее: этого требует `bob.jar` Defold 1.13 |
| `bash` | 4 или новее. На Mac это должен быть `/opt/homebrew/bin/bash` (или `/usr/local/bin/bash`), а не `/bin/bash` 3.2 |
| `Xvfb`, `VirtualGL` | только Linux: путь найден |
| `GPU` | настоящая видеокарта (на Linux — `OpenGL renderer` через VirtualGL), не `llvmpipe` и не `not found` |
| `agent` | `running on TCP 47800` |
| `broadcast` | `answers UDP 47800` |

## 4. Основной ПК: хост виден

```bash
python3 build_shell/test/test_host.py hosts
```

Должна быть строка с каждым хостом: имя, IP, ОС, свободная и общая RAM, под ней — какие программы занимают
больше всего памяти. Пример:

```text
this PC: 14133 of 31943 MB free, a test host is used below 6144 MB
macbook (192.168.0.57, Darwin) 9120 MB free of 16384 MB
    most memory: Google Chrome Helper 2410 MB, Figma 1320 MB, java 980 MB, WindowServer 610 MB, Finder 120 MB
```

`OLD AGENT` в строке означает агента, который ещё не умеет обновляться сам: один раз повтори на нём шаги 1 и 2.

## 5. Пробная сборка на хосте

Сборку можно принудительно отправить на хост, не дожидаясь нехватки RAM. Запускать из worktree:

```bash
LINUX_TEST_HOST=<IP хоста> build_shell/test/linux_test.sh --config=sound.gain=0
```

В выводе должны быть `ENGINE_PORT=...`, `ENGINE_LOG=...` и `ENGINE_HOST=<IP хоста>`. Первая сборка дольше
обычной: на хост один раз уходят весь проект и `bob.jar`.

## Обновить или удалить агент

- Обновлять не нужно: перед каждой удалённой сборкой основной ПК сам отправляет агенту свой `test_host.py`, если
  тот отличается, и агент перезапускается с ним (запущенные игры при этом не закрываются). Переустановка (шаги 1 и
  2) нужна, только если `hosts` пишет `OLD AGENT`.
- Удалить на Linux:

  ```bash
  systemctl --user disable --now defold-test-host.service && rm -rf ~/.config/systemd/user/defold-test-host.service ~/defold_test_host ~/test_host.py
  ```

- Удалить на Mac:

  ```bash
  launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/defold.test-host.plist; rm -rf ~/Library/LaunchAgents/defold.test-host.plist ~/defold_test_host ~/test_host.py
  ```

## Если не работает

- `hosts` не видит хост, а `check` на хосте пишет `OK` для `agent`. Широковещание не проходит между
  устройствами: часто это «изоляция клиентов» или гостевая сеть Wi-Fi в роутере. Подключи оба компьютера к одной
  обычной сети. Ещё одна причина — включённый файрвол macOS: разреши Python входящие подключения.
- `broadcast: no answer` на самом хосте — агент не запущен или порт 47800 занят. Повтори строку установки и
  посмотри `~/defold_test_host/agent.log` (Mac) или `journalctl --user -u defold-test-host` (Linux).
- Mac пропадает из списка — он уснул. Строка установки отключает сон только при питании от сети.
- Ошибка сборки на хосте — её вывод печатается в терминал основного ПК. Логи заданий лежат в
  `~/defold_test_host/jobs` на хосте.
