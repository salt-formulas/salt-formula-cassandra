cassandra:
  backup:
    server:
      enabled: true
      full_backups_to_keep: 3
      incr_before_full: 3
      backup_dir: /srv/backup
      backup_times:
        dayOfWeek: 0
#       month: *
#       dayOfMonth: *
        hour: 4
        minute: 52
      key:
        cassandra_pub_key:
          enabled: true
          key: key