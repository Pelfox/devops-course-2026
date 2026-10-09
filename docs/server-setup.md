# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

| Параметр                        | Значение                         |
| ------------------------------- | -------------------------------- |
| Наименование виртуальной машины | `devops-vm`                      |
| Средство виртуализации          | VirtualBox 7.x                   |
| Операционная система            | Ubuntu Server 24.04 LTS (64-bit) |
| Оперативная память              | 2048 МБ (2 ГБ)                   |
| Количество ядер процессора      | 2                                |
| Дисковый накопитель             | 25 ГБ, динамически расширяемый   |
| Имя узла (hostname)             | `devops-vm`                      |
| Полное имя узла (FQDN)          | `devops-vm.devops.local`         |

Проверка параметров внутри виртуальной машины:

```bash
hostnamectl
hostname -f
free -h
nproc
lsblk
```

## 2. Сетевые интерфейсы

| Адаптер | Тип       | Адрес IPv4     | Назначение                                                           |
| ------- | --------- | -------------- | -------------------------------------------------------------------- |
| 1       | NAT       | `10.0.2.15`    | Выход виртуальной машины в Интернет, установка и обновление пакетов. |
| 2       | Host-only | `192.168.56.2` | Прямое взаимодействие хостовой системы и виртуальной машины.         |

Фактические адреса определяются командой:

```bash
ip -brief address
```

Для локального имени `devops.local` в файле `hosts` **хостовой** системы указывается **фактический** адрес адаптера Host-only:

```text
192.168.56.2    devops.local
```

На виртуальной машине задаётся имя:

```bash
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f
```

## 3. Правило проброса портов

Проброс настраивается для **адаптера 1 (NAT)** в VirtualBox.

| Параметр                  | Значение    |
| ------------------------- | ----------- |
| Название правила          | `ssh`       |
| Протокол                  | TCP         |
| IP-адрес хостовой системы | `127.0.0.1` |
| Порт хостовой системы     | `2222`      |
| IP-адрес гостевой системы | Пустое поле |
| Порт гостевой системы     | `2222`      |

**Важно:** при первоначальной установке SSH порт гостевой системы был `22`. После усиления защиты SSH он изменён на `2222`, и правило VirtualBox должно быть обновлено.

Подключение после настройки:

```bash
ssh -i ~/.ssh/devops_vm -p 2222 devops@127.0.0.1
```

## 4. Учётные записи

| Учётная запись | Назначение                                     | Группы / права                                           | Способ доступа                                                                 |
| -------------- | ---------------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `student`      | Пользователь, созданный при установке.         | Административная учётная запись, созданная установщиком. | Первоначальный вход; после настройки `AllowUsers devops` вход по SSH запрещён. |
| `devops`       | Пользователь для удалённого администрирования. | `sudo`                                                   | SSH по ключу Ed25519.                                                          |
| `root`         | Системное администрирование.                   | UID 0                                                    | Прямой вход по SSH запрещён (`PermitRootLogin no`).                            |

Создание административной учётной записи:

```bash
sudo adduser devops
sudo usermod -aG sudo devops
groups devops
```

На **хостовой системе** создаётся ключевая пара:

```bash
ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm
```

Затем публичный ключ переносится на сервер (до отключения парольной аутентификации):

```bash
ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1
```

На сервере для учётной записи `devops` ключ находится в `~/.ssh/authorized_keys`. Требуемые права:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
stat -c '%a %n' ~/.ssh ~/.ssh/authorized_keys
```

В файле `~/.ssh/config` **хостовой системы** задаётся:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

После этого подключение выполняется командой:

```bash
ssh devops
```

## 5. Служба SSH

Основной файл конфигурации: `/etc/ssh/sshd_config` (не изменяется напрямую).

Резервная копия: `/etc/ssh/sshd_config.backup`.

Файл усиления защиты: `/etc/ssh/sshd_config.d/99-hardening.conf`.

Содержимое файла `/etc/ssh/sshd_config.d/99-hardening.conf`:

```sshconfig
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

**Порядок настройки:**

1. Убедиться, что SSH-вход по ключу для `devops` работает. **Не закрывать текущую рабочую SSH-сессию.**
2. Сохранить основной файл и создать конфигурацию:

   ```bash
   sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
   sudo nano /etc/ssh/sshd_config.d/99-hardening.conf
   ```

3. Проверить возможный конфликт с более ранним файлом `50-cloud-init.conf`: первое встреченное значение параметра может иметь приоритет.

   ```bash
   grep -r 'PasswordAuthentication' /etc/ssh/sshd_config.d/ /etc/ssh/sshd_config
   ```

   При необходимости закомментировать конфликтующую строку `PasswordAuthentication yes`.

4. Проверить синтаксис и эффективные параметры:

   ```bash
   sudo sshd -t
   sudo sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)'
   ```

5. Отключить сокетную активацию и запустить службу SSH:

   ```bash
   sudo systemctl disable --now ssh.socket
   sudo systemctl enable --now ssh.service
   sudo systemctl restart ssh
   sudo ss -tlnp | grep sshd
   ```

6. Изменить в VirtualBox порт гостевой системы в правиле NAT с `22` на `2222`. В **отдельном терминале** проверить команду `ssh devops`.

Ожидаемые ключевые параметры: `port 2222`, `permitrootlogin no`, `passwordauthentication no`, `maxauthtries 3`. Ожидаемый порт прослушивания SSH: `2222/tcp`.

## 6. Правила межсетевого экрана

Используется `ufw`.

| Параметр                    | Значение |
| --------------------------- | -------- |
| Состояние                   | `active` |
| Политика входящего трафика  | `deny`   |
| Политика исходящего трафика | `allow`  |
| Журналирование              | `medium` |

Итоговые разрешающие правила:

| Порт/протокол | Правило | Назначение                             |
| ------------- | ------- | -------------------------------------- |
| `2222/tcp`    | `LIMIT` | SSH с ограничением частоты подключений |
| `80/tcp`      | `ALLOW` | HTTP, для практической работы № 6      |
| `443/tcp`     | `ALLOW` | HTTPS                                  |

Последовательность настройки (**правило SSH создаётся до включения UFW**):

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable

# После проверки, что новое SSH-подключение работает:
sudo ufw delete allow 2222/tcp
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
```

Проверка итоговой конфигурации:

```bash
sudo ufw status verbose
sudo ufw status numbered
sudo grep 'UFW BLOCK' /var/log/ufw.log | tail -5
```

**Предупреждение:** не включайте UFW, пока не разрешён фактический порт службы SSH. Команда `sudo ufw allow ssh` обычно разрешает `22/tcp` согласно `/etc/services`, а не изменённый порт `2222/tcp`.
