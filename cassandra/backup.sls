{%- from "cassandra/map.jinja" import backup with context %}

{%- if backup.client is defined %}

{%- if backup.client.enabled %}

cassandra_backup_client_packages:
  pkg.installed:
  - names: {{ backup.pkgs }}

cassandra_get_listen_addr_script:
  file.managed:
  - name: /usr/local/bin/cas_get_listen_addr
  - source: salt://cassandra/files/backup/cas_get_listen_addr.py
  - template: jinja
  - mode: 555

cassandra_backup_runner_script:
  file.managed:
  - name: /usr/local/bin/cassandra-backup-runner.sh
  - source: salt://cassandra/files/backup/cassandra-backup-client-runner.sh
  - template: jinja
  - mode: 655
  - require:
    - pkg: cassandra_backup_client_packages
    - file: cassandra_get_listen_addr_script

cassandra_call_backup_runner_script:
  file.managed:
  - name: /usr/local/bin/cassandra-backup-runner-call.sh
  - source: salt://cassandra/files/backup/cassandra-backup-client-runner-call.sh
  - template: jinja
  - mode: 655
  - require:
    - pkg: cassandra_backup_client_packages
    - file: cassandra_get_listen_addr_script

cassandra_backup_dir:
  file.directory:
  - name: {{ backup.backup_dir }}/full
  - user: root
  - group: root
  - makedirs: true

cassandra_backup_runner_cron:
  cron.present:
  - name: /usr/local/bin/cassandra-backup-runner-call.sh
  - user: root
{%- if not backup.cron %}
  - commented: True
{%- endif %}
{%- if backup.client.backup_times is defined %}
{%- if backup.client.backup_times.dayOfWeek is defined %}
  - dayweek: {{ backup.client.backup_times.dayOfWeek }}
{%- endif -%}
{%- if backup.client.backup_times.month is defined %}
  - month: {{ backup.client.backup_times.month }}
{%- endif %}
{%- if backup.client.backup_times.dayOfMonth is defined %}
  - daymonth: {{ backup.client.backup_times.dayOfMonth }}
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


{%- if backup.client.restore_latest is defined %}

cassandra_backup_restore_script:
  file.managed:
  - name: /usr/local/bin/cassandra-backup-restore.sh
  - source: salt://cassandra/files/backup/cassandra-backup-client-restore.sh
  - template: jinja
  - mode: 655
  - require:
    - pkg: cassandra_backup_client_packages
    - file: cassandra_get_listen_addr_script

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

{%- for key_name, key in backup.server.key.iteritems() %}

{%- if key.get('enabled', False) %}

{%- set clients = [] %}
{%- if backup.restrict_clients %}
  {%- for node_name, node_grains in salt['mine.get']('*', 'grains.items').iteritems() %}
    {%- if node_grains.get('cassandra', {}).get('backup', {}).get('client') %}
    {%- set client = node_grains.get('cassandra').get('backup').get('client') %}
      {%- if client.get('addresses') and client.get('addresses', []) is iterable %}
        {%- for address in client.addresses %}
          {%- do clients.append(address|string) %}
        {%- endfor %}
      {%- endif %}
    {%- endif %}
  {%- endfor %}
{%- endif %}

cassandra_key_{{ key.key }}:
  ssh_auth.present:
  - user: cassandra
  - name: {{ key.key }}
  - options:
    - no-pty
{%- if clients %}
    - from="{{ clients|join(',') }}"
{%- endif %}
  - require:
    - file: {{ backup.backup_dir }}/full

{%- endif %}

{%- endfor %}

cassandra_server_script:
  file.managed:
  - name: /usr/local/bin/cassandra-backup-runner.sh
  - source: salt://cassandra/files/backup/cassandra-backup-server-runner.sh
  - template: jinja
  - mode: 655
  - require:
    - pkg: cassandra_backup_server_packages

cassandra_server_cron:
  cron.present:
  - name: /usr/local/bin/cassandra-backup-runner.sh
  - user: cassandra
{%- if not backup.cron %}
  - commented: True
{%- endif %}
  - minute: 0
  - hour: 2
  - require:
    - file: cassandra_server_script

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
