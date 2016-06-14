{%- if pillar.cassandra is defined %}
include:
{%- if pillar.cassandra.server is defined %}
- cassandra.server
{%- endif %}
{%- endif %}
