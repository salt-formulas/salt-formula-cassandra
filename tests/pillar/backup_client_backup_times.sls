cassandra:
  backup:
    client:
      enabled: true
      full_backups_to_keep: 3
      incr_before_full: 3
      backup_times:
        dayOfWeek: 0
#       month: *
#       dayOfMonth: *
        hour: 4
        minute: 52
      target:
        host: cfg01
      restore_latest: 1
      restore_from: local