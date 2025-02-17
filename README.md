# usage: #
backup.sh <hostname> local

# Dependencies: #
rsync - for backing up files
mysql - if you want to backup mysql db's
bc - calculations

## NOTE: #
Backing up over SSH assumes you have a profile for the target setup in your ~/.ssh/config file.

Usage: $0 [OPTIONS]

Options:
  --target=<name>      Specify the backup target.
  --local              Run the script in local mode.
  --mysqluser=<user>   Override the default MySQL username.
  --mysqlpass=<pass>   Specify the MySQL password.
  --help               Display this help message.

Examples:
  $0 --target=production
  $0 --local
  $0 --mysqluser=admin
  $0 --mysqluser=admin --mysqlpass=supersecure
  $0 --target=staging --local --mysqluser=admin --mysqlpass=topsecret

### TODO
- [ ] source ~/.backup.conf for settings
- [ ] REALLY test and fix deleting old backups
- [x] add -l switch for local
- [x] remove the whole "bastion" thing. We should use ssh ProxyJump instead
- [x] remove bc as a dependency
