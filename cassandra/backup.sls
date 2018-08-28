{%- from "cassandra/map.jinja" import backup with context %}

{%- if backup.client is defined %}

{%- if backup.client.enabled %}

cassandra_backup_client_packages:
  pkg.installed:
  - names: {{ backup.pkgs }}

cassandra_backup_runner_script:
  file.managed:
  - name: /usr/local/bin/cassandra-backup-runner.sh
  - source: salt://cassandra/files/backup/cassandra-backup-client-runner.sh
  - template: jinja
  - mode: 655
  - require:
    - pkg: cassandra_backup_client_packages

cassandra_call_backup_runner_script:
  file.managed:
  - name: /usr/local/bin/cassandra-backup-runner-call.sh
  - source: salt://cassandra/files/backup/cassandra-backup-client-runner-call.sh
  - template: jinja
  - mode: 655
  - require:
    - pkg: cassandra_backup_client_packages

cassandra_backup_dir:
  file.directory:
  - name: {{ backup.backup_dir }}/full
  - user: root
  - group: root
  - makedirs: true

{%- if backup.cron %}

cassandra_backup_runner_cron:
  cron.present:
  - name: /usr/local/bin/cassandra-backup-runner-call.sh
  - user: root
{%- if backup.client.backup_times is defined %}
{%- if backup.client.backup_times.day_of_week is defined %}
  - dayweek: {{ backup.client.backup_times.day_of_week }}
{%- endif -%}
{%- if backup.client.backup_times.month is defined %}
  - month: {{ backup.client.backup_times.month }}
{%- endif %}
{%- if backup.client.backup_times.day_of_month is defined %}
  - daymonth: {{ backup.client.backup_times.day_of_month }}
{%- endif %}
{%- if backup.client.backup_times.hour is defined %}
  - hour: {{ backup.client.backup_times.hour }}
{%- endif %}
{%- if backup.client.backup_times.minute is defined %}
  - minute: {{ backup.client.backup_times.minute }}
{%- endif %}
{%- elif backup.client.hours_before_incr is defined %}
  - minute: 0
{%- if backup.client.hours_before_full <= 23 and backup.client.hours_before_full > 1 %}
  - hour: '*/{{ backup.client.hours_before_full }}'
{%- elif not backup.client.hours_before_full <= 1 %}
  - hour: 2
{%- endif %}
{%- else %}
  - hour: 2
{%- endif %}
  - require:
    - file: cassandra_backup_runner_script
    - file: cassandra_call_backup_runner_script

{%- else %}

cassandra_backup_runner_cron:
  cron.absent:
  - name: /usr/local/bin/cassandra-backup-runner-call.sh
  - user: root

{%- endif %}

{%- if backup.client.restore_latest is defined %}

cassandra_backup_restore_script:
  file.managed:
  - name: /usr/local/bin/cassandra-backup-restore.sh
  - source: salt://cassandra/files/backup/cassandra-backup-client-restore.sh
  - template: jinja
  - mode: 655
  - require:
    - pkg: cassandra_backup_client_packages

cassandra_backup_call_restore_script:
  file.managed:
  - name: /usr/local/bin/cassandra-backup-restore-call.sh
  - source: salt://cassandra/files/backup/cassandra-backup-client-restore-call.sh
  - template: jinja
  - mode: 655
  - require:
    - file: cassandra_backup_restore_script

cassandra_run_restore:
  cmd.run:
  - name: /usr/local/bin/cassandra-backup-restore-call.sh
  - unless: "[ -e {{ backup.backup_dir }}/dbrestored ]"
  - require:
    - file: cassandra_backup_call_restore_script

{%- endif %}

{%- endif %}

{%- endif %}

{%- if backup.server is defined %}

{%- if backup.server.enabled %}

cassandra_backup_server_packages:
  pkg.installed:
  - names: {{ backup.pkgs }}

cassandra_user:
  user.present:
  - name: cassandra
  - system: true
  - home: {{ backup.backup_dir }}

{{ backup.backup_dir }}/full:
  file.directory:
  - mode: 755
  - user: cassandra
  - group: cassandra
  - makedirs: true
  - require:
    - user: cassandra_user
    - pkg: cassandra_backup_server_packages

{{ backup.backup_dir }}/.ssh:
  file.directory:
  - mode: 700
  - user: cassandra
  - group: cassandra
  - require:
    - user: cassandra_user

{{ backup.backup_dir }}/.ssh/authorized_keys:
  file.managed:
  - user: cassandra
  - group: cassandra
  - template: jinja
  - source: salt://cassandra/files/backup/authorized_keys
  - require:
    - file: {{ backup.backup_dir }}/full
    - file: {{ backup.backup_dir }}/.ssh

cassandra_server_script:
  file.managed:
  - name: /usr/local/bin/cassandra-backup-runner.sh
  - source: salt://cassandra/files/backup/cassandra-backup-server-runner.sh
  - template: jinja
  - mode: 655
  - require:
    - pkg: cassandra_backup_server_packages

{%- if backup.cron %}

cassandra_server_cron:
  cron.present:
  - name: /usr/local/bin/cassandra-backup-runner.sh
  - user: cassandra
  - minute: 0
  - hour: 2
  - require:
    - file: cassandra_server_script

{%- else %}

cassandra_server_cron:
  cron.absent:
  - name: /usr/local/bin/cassandra-backup-runner.sh
  - user: cassandra

{%- endif %}

cassandra_server_call_restore_script:
  file.managed:
  - name: /usr/local/bin/cassandra-restore-call.sh
  - source: salt://cassandra/files/backup/cassandra-backup-server-restore-call.sh
  - template: jinja
  - mode: 655
  - require:
    - pkg: cassandra_backup_server_packages

{%- endif %}

{%- endif %}
