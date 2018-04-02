# openshift-mta
MTA in a Docker primary designed for secure Openshift environment
## Proof on Concept
I'm trying to setup a stable MTA in a secure openshift environment.

## Test environment
I'm pretest the different proof of concepts on my local docker machine.

```
docker run --rm -u 1000120000 --group-add 1000120000 --name <variant> <variant>
```

# liblogfaf
This is a smail library that should be preloaded with `LD_PRELOAD`. The wraps the functions `syslog` and `__syslog_chk` to
send messages to `stdout` or whatever you want.

Source: https://github.com/jkroepke/liblogfaf

# Variants

| Program | In RHEL7 | Status | Requires liblogfaf | Notes |
| ------- | ------ | ------ | ------ | ------ |
| Postfix | YES | __FAILED__ | YES | master process can be run without root but childs failed. Many hacks like fakeroot required but it didn't work at the end. |
| exim | EPEL | __FAILED__ | N/A | Exim documentation says, exim can be run in rootless, but can't detect to unpriviliged mode and want to call `setgroup` |
| sendmail | YES | __SUCCESS__ | YES | Configuration syntax from last century. [Hardcoded 60 second sleep phase at startup](https://github.com/aosm/sendmail/blob/0b43ef09c7fa82f822b17cb8a060f673280663cc/sendmail/sendmail/daemon.c#L3184), if `hostname -f` isn't a FQDN.|
| msmtp | EPEL | __UNKNOWN__ | N/A | - |
| nullmailer | NO | __UNKNOWN__ | N/A |  - |
| haraka | NO | __UNKNOWN__ | N/A | nodejs MTA |
| zone-mta | NO | __UNKNOWN__ | N/A | nodejs MTA |