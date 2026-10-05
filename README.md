# MasterLaplace/.github

The files every public repository of this account shows when it has none of its own: the code of
conduct, how to contribute, the security policy, where to get support, the issue and pull request
forms, and the form for reporting a breach of the code of conduct.

`etabli.json` declares how the Laplace repositories are kept: labels, merge settings, security
switches and branch rules. It is applied by `forgeron etabli` from
[LplCraftSkills](https://github.com/MasterLaplace/LplCraftSkills):

```bash
python3 -m forgeron etabli --file etabli.json            # the plan, nothing is written
python3 -m forgeron etabli --file etabli.json --write    # apply, then read again
```

`templates/config.h` is the header every Laplace repository copies under its own prefix: its name,
its version, the build it went into, what it needs from the other repositories, and where it runs.
`tools/check-config-header.sh` compares a copy with the template, and `--write` brings a copy back to
it:

```bash
tools/check-config-header.sh ../LplKernel/kernel/include/kernel/config.h KERNEL
tools/test-config-header.sh                                   # the template and the check, tested
```

A change to any of these goes through a pull request here, like code.
