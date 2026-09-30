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

A change to either goes through a pull request here, like code.
