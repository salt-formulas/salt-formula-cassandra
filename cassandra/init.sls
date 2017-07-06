{%- if pillar.cassandra is defined %}
include:
{%- if pillar.cassandra.server is defined %}
- cassandra.server
{%- endif %}
{%- if pillar.cassandra.backup is defined %}
- cassandra.backup
{%- endif %}
{%- endif %}
