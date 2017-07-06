cassandra:
  backup:
    client:
      enabled: true
      full_backups_to_keep: 3
      hours_before_full: 24
      target:
        host: cfg01
      restore_latest: 1
      restore_from: local