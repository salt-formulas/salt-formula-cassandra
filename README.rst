
==================================
cassandra
==================================

Service cassandra description

Sample pillars
==============

Single cassandra service

.. code-block:: yaml

    cassandra:
      server:
        enabled: true
        version: icehouse

Backup client with ssh/rsync remote host

.. code-block:: yaml

    cassandra:
      backup:
        client:
          enabled: true
          full_backups_to_keep: 3
          hours_before_full: 24
          target:
            host: cfg01
            home_dir: server-home-dir

  .. note:: full_backups_to_keep param states how many backup will be stored locally on cassandra client.
            More options to relocate local backups can be done using salt-formula-backupninja.


Backup client with local backup only

.. code-block:: yaml

    cassandra:
      backup:
        client:
          enabled: true
          full_backups_to_keep: 3
          hours_before_full: 24

  .. note:: full_backups_to_keep param states how many backup will be stored locally on cassandra client


Backup client at exact times:

..code-block:: yaml

  cassandra:
    backup:
      client:
        enabled: true
        full_backups_to_keep: 3
        incr_before_full: 3
        backup_times:
          dayOfWeek: 0
          hour: 4
          minute: 52
        compression: true
        compression_threads: 2
        database:
          user: user
          password: password
        target:
          host: host01

  .. note:: Parameters in ``backup_times`` section can be used to set up exact
  time the cron job should be executed. In this example, the backup job
  would be executed every Sunday at 4:52 AM. If any of the individual
  ``backup_times`` parameters is not defined, the defalut ``*`` value will be
  used. For example, if minute parameter is ``*``, it will run the backup every minute,
  which is ususally not desired.
  Available parameters are ``dayOfWeek``, ``dayOfMonth``, ``month``, ``hour`` and ``minute``.
  Please see the crontab reference for further info on how to set these parameters.

  .. note:: Please be aware that only ``backup_times`` section OR
  ``hours_before_full(incr)`` can be defined. If both are defined,
  the ``backup_times`` section will be peferred.

  .. note:: New parameter ``incr_before_full`` needs to be defined. This
  number sets number of incremental backups to be run, before a full backup
  is performed.


Backup server rsync

.. code-block:: yaml

    cassandra:
      backup:
        server:
          enabled: true
          hours_before_full: 24
          full_backups_to_keep: 5
          key:
            cassandra_pub_key:
              enabled: true
              key: ssh_rsa

Backup server without strict client restriction

.. code-block:: yaml

    cassandra:
      backup:
        restrict_clients: false

Backup server at exact times:

..code-block:: yaml

  cassandra:
    backup:
      server:
        enabled: true
        full_backups_to_keep: 3
        incr_before_full: 3
        backup_dir: /srv/backup
        backup_times:
          dayOfWeek: 0
          hour: 4
          minute: 52
        key:
          cassandra_pub_key:
            enabled: true
            key: key

  .. note:: Parameters in ``backup_times`` section can be used to set up exact
  time the cron job should be executed. In this example, the backup job
  would be executed every Sunday at 4:52 AM. If any of the individual
  ``backup_times`` parameters is not defined, the defalut ``*`` value will be
  used. For example, if minute parameter is ``*``, it will run the backup every minute,
  which is ususally not desired.
  Available parameters are ``dayOfWeek``, ``dayOfMonth``, ``month``, ``hour`` and ``minute``.
  Please see the crontab reference for further info on how to set these parameters.

  .. note:: Please be aware that only ``backup_times`` section OR
  ``hours_before_full(incr)`` can be defined. If both are defined, The
  ``backup_times`` section will be peferred.

  .. note:: New parameter ``incr_before_full`` needs to be defined. This
  number sets number of incremental backups to be run, before a full backup
  is performed.

Client restore from local backup:

.. code-block:: yaml

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

  .. note:: restore_latest param with a value of 1 means to restore db from the last full backup. 2 would mean to restore second latest full backup.

Client restore from remote backup:

.. code-block:: yaml

    cassandra:
      backup:
        client:
          enabled: true
          full_backups_to_keep: 3
          hours_before_full: 24
          target:
            host: cfg01
          restore_latest: 1
          restore_from: remote

  .. note:: restore_latest param with a value of 1 means to restore db from the last full backup. 2 would mean to restore second latest full backup.



Read more
=========

* links

Documentation and Bugs
======================

To learn how to install and update salt-formulas, consult the documentation
available online at:

    http://salt-formulas.readthedocs.io/

In the unfortunate event that bugs are discovered, they should be reported to
the appropriate issue tracker. Use Github issue tracker for specific salt
formula:

    https://github.com/salt-formulas/salt-formula-cassandra/issues

For feature requests, bug reports or blueprints affecting entire ecosystem,
use Launchpad salt-formulas project:

    https://launchpad.net/salt-formulas

You can also join salt-formulas-users team and subscribe to mailing list:

    https://launchpad.net/~salt-formulas-users

Developers wishing to work on the salt-formulas projects should always base
their work on master branch and submit pull request against specific formula.

    https://github.com/salt-formulas/salt-formula-cassandra

Any questions or feedback is always welcome so feel free to join our IRC
channel:

    #salt-formulas @ irc.freenode.net
