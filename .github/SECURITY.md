# Security policy

## Supported versions

Fixes go to the latest release and to the default branch. Older releases do not receive them: update
to the latest one.

## Reporting a vulnerability

Do not open a public issue or discussion for a vulnerability.

Report it privately from the repository's **Security** tab, with **Report a vulnerability**. The
report opens a draft security advisory that only you and the maintainer can read.

A useful report says:

- what an attacker can do, and what they need to do it;
- the version or commit where you saw it;
- the smallest steps that show it;
- what you think would fix it, if you have an idea.

## What happens next

1. The maintainer acknowledges the report in the advisory, within 7 days. This is a personal project
   maintained in spare time: the delay is a target, not a contract.
2. The fix is prepared in a temporary private fork attached to the advisory, where you can follow it
   and review it.
3. A release carries the fix.
4. The advisory is then published, with the details, the affected and fixed versions, and credit to
   you unless you prefer otherwise. GitHub assigns it a CVE identifier.

## Disclosure

Everything becomes public, after the fix and not before: until a fixed release exists, a public
description is a recipe for attackers while users are not yet protected. If no fix exists 90 days
after the report, the advisory is published anyway, with what users can do to protect themselves.
