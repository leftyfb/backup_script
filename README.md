# usage: #
backup.sh <hostname> local

# Dependencies: #
rsync - for backing up files
mysql - if you want to backup mysql db's

## NOTE: #
To backup locally without ssh, type local after the hostname.
To use ssh keys, setup your ~/.ssh/config for the hostname.

### TODO
- [ ] source ~/.backup.conf for settings
- [ ] REALLY test and fix deleting old backups
- [ ] add -l switch for local
- [x] remove the whole "bastion" thing. We should use ssh ProxyJump instead
- [x] remove bc as a dependency
