cassandra:
  server:
    enabled: true
    version: 2
    name: 'cassandra'
    bind:
      address: 127.0.0.1
      rpc_port: 9160
    members:
    - host: 127.0.0.1
    - host: 127.0.1.1
    - host: 127.0.2.1