{%- from "cassandra/map.jinja" import server with context %}
{%- if server.enabled %}

cassandra_server_packages:
  pkg.installed:
  - names: {{ server.pkgs }}

/etc/cassandra/cassandra.yaml:
  file.managed:
  - source: salt://cassandra/files/{{ server.version }}/cassandra.yaml
  - template: jinja
  - require:
    - pkg: cassandra_server_packages

cassandra_server_services:
  service.running:
  - names: {{ server.services }}
  - enable: true
  - watch:
    - file: /etc/cassandra/cassandra.yaml

{%- if grains.get('virtual_subtype', None) == "Docker" %}

cassandra_entrypoint:
  file.managed:
  - name: /entrypoint.sh
  - template: jinja
  - source: salt://cassandra/files/entrypoint.sh
  - mode: 755

{%- endif %}

{%- endif %}
