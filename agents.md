# Agent Guidelines

## Git commit guidelines

Ask whether the commit was co-authored by somebody. List of authors: `git log --format="%an <%ae>" | sort -u | grep "@digitalservice.bund.de"`
In that case, we add the typical Co-Authored-By suffix to the commit message.

## Reading Platform documentation:

The platform docs are protected with Basic Auth on this URL: https://platform-docs.prod.tech.digitalservice.dev/

Read username/password from 1Password

Username: `op read "op://44647uhat7og6qb7x3y5pikdiq/prmtirsbpd64m4nx2y26vhhkbu/username"`
Password: `op read "op://44647uhat7og6qb7x3y5pikdiq/prmtirsbpd64m4nx2y26vhhkbu/password"`

Example `curl` command:

```
curl -u "$(op read "op://44647uhat7og6qb7x3y5pikdiq/prmtirsbpd64m4nx2y26vhhkbu/username"):$(op read "op://44647uhat7og6qb7x3y5pikdiq/prmtirsbpd64m4nx2y26vhhkbu/password")" https://platform-docs.prod.tech.digitalservice.dev/
```
