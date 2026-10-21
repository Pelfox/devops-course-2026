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


## 8. Веб-сервер

### 8.1. Установка и расположение файлов

| Параметр                         | Значение                                                                   |
| -------------------------------- | -------------------------------------------------------------------------- |
| Веб-сервер                       | Nginx (`nginx`, устанавливается через `apt`)                               |
| Служба systemd                   | `nginx.service`                                                            |
| Основной файл конфигурации       | `/etc/nginx/nginx.conf`                                                    |
| Файл конфигурации ресурса        | `/etc/nginx/sites-available/devops-site`                                   |
| Активный ресурс                  | Ссылка `/etc/nginx/sites-enabled/devops-site` на файл из `sites-available` |
| Стандартный ресурс               | Ссылка `/etc/nginx/sites-enabled/default` удалена                          |
| Каталог ресурса                  | `/var/www/devops-site`                                                     |
| Владелец каталога и файлов       | `devops:devops`                                                            |
| Права каталогов                  | `755` (`drwxr-xr-x`)                                                       |
| Права файлов                     | `644` (`-rw-r--r--`)                                                       |
| Учётная запись рабочих процессов | `www-data` (чтение без права записи)                                       |
| Домен                            | `devops.local`                                                             |
| HTTP                             | `80/tcp`: постоянное перенаправление `301` на HTTPS                        |
| HTTPS                            | `443/tcp`: TLS 1.2 и 1.3                                                   |
| Журнал обращений                 | `/var/log/nginx/devops-site.access.log`                                    |
| Журнал ошибок                    | `/var/log/nginx/devops-site.error.log`                                     |

Установка и подготовка каталога (выполняется на виртуальной машине):

```bash
sudo apt update && sudo apt install -y nginx
sudo mkdir -p /var/www/devops-site
sudo chown -R devops:devops /var/www/devops-site
sudo find /var/www/devops-site -type d -exec chmod 755 {} +
sudo find /var/www/devops-site -type f -exec chmod 644 {} +
```

### 8.2. HTTPS-сертификат и закрытый ключ

| Параметр                         | Значение                                              |
| -------------------------------- | ----------------------------------------------------- |
| Сертификат                       | `/etc/ssl/certs/devops.crt`                           |
| Владелец и права сертификата     | `root:root`, `644`                                    |
| Закрытый ключ                    | `/etc/ssl/private/devops.key`                         |
| Владелец и права закрытого ключа | `root:root`, `600`                                    |
| Тип сертификата                  | Самоподписанный, RSA 2048                             |
| Имя сертификата                  | `CN=devops.local` и `subjectAltName=DNS:devops.local` |
| Срок действия                    | **365 дней с момента выпуска**                        |
| Протоколы                        | TLSv1.2, TLSv1.3                                      |

Команда формирования сертификата:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
sudo chown root:root /etc/ssl/private/devops.key /etc/ssl/certs/devops.crt
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
```

Приватный ключ нельзя переносить в репозиторий. На хостовую машину по доверенному SSH-каналу переносится только сертификат:

```bash
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
curl --cacert ~/devops.crt -I https://devops.local
```

### 8.3. Конфигурация ресурса Nginx

Содержимое `/etc/nginx/sites-available/devops-site`:

```nginx
# Перенаправление HTTP -> HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}

# Раздача статического сайта по HTTPS
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;

    ssl_certificate     /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/devops-site;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;

    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
```

> Если IPv6 отключён, удалите строки `listen [::]:80;` и `listen [::]:443 ssl;` перед проверкой Nginx. Заголовок HSTS в этой учебной конфигурации не добавляется.

Активация ресурса и применение конфигурации:

```bash
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/devops-site
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

### 8.4. Доставка и контроль

Файлы статического сайта хранятся в каталоге `site/` репозитория и публикуются в `/var/www/devops-site/` через `scripts/deploy.sh`.

Проверки с хостовой системы:

```bash
curl -I http://devops.local                 # 301 -> https://devops.local/
curl --cacert ~/devops.crt -I https://devops.local   # 200 OK
scripts/deploy.sh --dry-run
scripts/deploy.sh
```

Проверки на виртуальной машине:

```bash
systemctl is-active nginx
sudo nginx -t
sudo ss -tlnp | grep nginx
ls -la /var/www/devops-site/
sudo stat -c '%U:%G %a %n' /etc/ssl/certs/devops.crt /etc/ssl/private/devops.key
sudo find /var/www/devops-site -perm -o+w
openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend 2592000
scripts/audit.sh; echo $?
```

## 9. Контейнеризация

### 9.1. Docker Engine и Docker Compose

Контейнеры размещаются на виртуальной машине `devops-vm` с Ubuntu Server 24.04 LTS. Docker Engine устанавливается **из официального APT-репозитория Docker**, а не из пакета Ubuntu `docker.io` (практическая работа № 7, подраздел 3.1). Для установки используются пакеты `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`. Служба `docker.service` запускается под управлением systemd.

Для воспроизведения установки см. [официальную инструкцию для Ubuntu](https://docs.docker.com/engine/install/ubuntu/). После добавления официального репозитория используются команды:

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

Для запуска Docker без `sudo` учётная запись `devops` (у неё также есть право `sudo`) должна быть добавлена в группу `docker`. После изменения состава группы требуется новая SSH-сессия:

```bash
sudo usermod -aG docker devops
getent group docker                         # проверить фактический список участников
id devops                                   # проверить docker и sudo
```

**Важно:** членство в группе `docker` фактически даёт возможность получить права root через Docker. Добавлять туда пользователей без разрешённого административного доступа нельзя.

### 9.2. Проект, приложение и конфиденциальные переменные

Репозиторий исходного кода: [Pelfox/devops-course-2026](https://github.com/Pelfox/devops-course-2026). На хостовой системе контейнерные файлы находятся в `app/` (`Dockerfile`, `app.py`, `requirements.txt`, `.dockerignore`, `docker-compose.yml`, `.env.example`). На ВМ они размещены в **`/home/devops/app/`**; проект Compose запускается из этого каталога под пользователем `devops`:

```bash
# На хостовой системе, из корня репозитория:
rsync -avz --delete --exclude=.env --dry-run app/ devops:app/
rsync -avz --delete --exclude=.env app/ devops:app/

# На ВМ:
cd /home/devops/app
docker compose up -d --build
docker compose ps
```

Файл с паролем PostgreSQL — **`/home/devops/app/.env`** — создаётся только на ВМ, должен принадлежать `devops` и иметь права **`600`**. В репозитории хранится исключительно `.env.example` с заглушкой. `app/.dockerignore` и `.gitignore` исключают `.env` из контекста сборки и из Git; при передаче по `rsync` обязательно сохраняется `--exclude=.env`, иначе `--delete` удалит секрет на сервере.

```bash
# На ВМ, выполнять один раз при первоначальной настройке:
cd /home/devops/app
cp .env.example .env
chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
stat -c '%U:%G %a %n' .env              # ожидается: devops:devops 600 .env

# В корне репозитория на хостовой системе:
git ls-files | grep -x 'app/.env'       # пустой вывод
```

Пароль из `.env` нельзя публиковать в отчёте, выводить на экран или копировать на хостовую систему. Приложение подключается к СУБД по `DB_HOST=db` через внутренний DNS сети Compose. Образ приложения — `devops-app:1.0`, запускаемый от непривилегированного пользователя `app`; образ PostgreSQL — `postgres:16-alpine`.

### 9.3. Сеть, порты и постоянное хранилище

Compose создаёт изолированную пользовательскую bridge-сеть **`app_backend`**, в которой работают сервисы `app` и `db`. Название `app` в префиксе сети и тома обусловлено запуском проекта из `/home/devops/app/` с именем проекта Compose по умолчанию.

| Компонент      | Адрес и порт                                        | Доступность                                                                        |
| -------------- | --------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Nginx HTTP     | `0.0.0.0:80` (также `[::]:80`, если IPv6 включён)   | Внешний HTTP; перенаправление на HTTPS                                             |
| Nginx HTTPS    | `0.0.0.0:443` (также `[::]:443`, если IPv6 включён) | Внешний HTTPS; статический сайт и `/app/`                                          |
| Flask/Gunicorn | **`127.0.0.1:5000:5000`**                           | Только localhost ВМ; Nginx подключается к `127.0.0.1:5000`                         |
| PostgreSQL     | `5432/tcp` внутри `app_backend`                     | **Не публикуется** на сетевых интерфейсах ВМ; доступен сервису `app` по имени `db` |

В `app/docker-compose.yml` для приложения задано `ports: ["127.0.0.1:5000:5000"]`, для `db` раздел `ports` отсутствует. Изменять публикацию на `5000:5000` нельзя: это открывает контейнер на всех интерфейсах, в том числе в обход обычных ограничений UFW из-за правил Docker в `iptables`.

Данные PostgreSQL находятся в именованном томе **`app_db_data`** (в Compose объявлен как `db_data`), подключённом к `/var/lib/postgresql/data` внутри контейнера. Команда `docker compose down` сохраняет том, а **`docker compose down -v` безвозвратно удаляет его содержимое**; для обычной остановки и обновления флаг `-v` не применяется. Том нужен для сохранения таблицы и счётчика посещений после пересоздания контейнеров.

```bash
cd /home/devops/app
docker network ls
docker volume ls
# Имя и расположение тома (Mountpoint) проверяются на конкретной ВМ:
docker volume inspect app_db_data
docker compose exec app getent hosts db
sudo ss -tlnp | grep -E ':(5000|5432)\b'  # только 127.0.0.1:5000; нет 5432
```

### 9.4. Публикация через обратный прокси Nginx

Nginx установлен непосредственно на ВМ, а не в Docker. Его конфигурация — `/etc/nginx/sites-available/devops-site`, активирована символьной ссылкой `/etc/nginx/sites-enabled/devops-site`. HTTP `:80` перенаправляется кодом 301 на HTTPS `:443`; сертификат `/etc/ssl/certs/devops.crt` и ключ `/etc/ssl/private/devops.key`. **Существующий статический сайт** `/var/www/devops-site` остаётся доступным по `https://devops.local/`.

В блоке `server` для HTTPS дополнительно расположен следующий фрагмент (полная конфигурация приведена в разделе 8.3):

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Завершающий `/` после порта в `proxy_pass` означает замену префикса `/app/`: запрос `/app/health` направляется в контейнер как `/health`. При остановке `app` Nginx возвращает `502 Bad Gateway`, подробности — в `/var/log/nginx/devops-site.error.log`.

```bash
# На ВМ:
sudo nginx -t && sudo systemctl reload nginx

# На хостовой системе:
curl --cacert ~/devops.crt https://devops.local/app/
curl --cacert ~/devops.crt https://devops.local/app/health   # ok
curl --cacert ~/devops.crt -I https://devops.local/       # 200 OK
```

### 9.5. Проверка и воспроизведение отрицательного результата аудита

Раздел `[5] Контейнеризация` сценария `scripts/audit.sh` проверяет активность Docker, состояние `healthy` у `app-db-1`, отсутствие TCP-прослушивания портов `5000` и `5432` на адресах, отличных от `127.0.0.1`, и права `600` для `/home/devops/app/.env`. Скрипт использует функцию `check` и возвращает `0`, когда все проверки разделов аудита пройдены, либо `1`, если есть ошибки.

```bash
# На хосте из корня репозитория: доставить аудит на ВМ
ssh devops 'mkdir -p ~/scripts'
rsync -av scripts/audit.sh devops:scripts/audit.sh

# На ВМ:
chmod +x ~/scripts/audit.sh
~/scripts/audit.sh; echo $?                 # 0, если все проверки выполнены
```

Для обязательной отрицательной проверки пункта 3.6 **временно** опубликовать порт Flask на всех интерфейсах, затем восстановить исходную конфигурацию (выполняется только на учебной ВМ):

```bash
cd /home/devops/app
cp docker-compose.yml docker-compose.yml.audit-backup
sed -i 's/127\.0\.0\.1:5000:5000/5000:5000/' docker-compose.yml
docker compose up -d
~/scripts/audit.sh; echo $?                  # ожидается 1: проверка портов [FAIL]

mv docker-compose.yml.audit-backup docker-compose.yml
docker compose up -d
~/scripts/audit.sh; echo $?                  # ожидается 0: все проверки [OK]
```

После теста убедиться, что публикация снова ограничена `127.0.0.1:5000`, база данных осталась в состоянии `healthy`, а проект продолжает работать.

