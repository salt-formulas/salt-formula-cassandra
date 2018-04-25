cassandra:
  backup:
    client:
      enabled: true
      full_backups_to_keep: 3
      incr_before_full: 3
      backup_times:
        day_of_week: 0
#       month: *
#       day_of_month: *
        hour: 4
        minute: 52
      target:
        host: cfg01
      restore_latest: 1
      restore_from: local