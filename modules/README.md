# `modules/`

Reusable module definitions. Environment-agnostic by construction: no
environment name, no CIDR, no instance count, and no account ID appears as a
literal in here. Everything that differs between `dev`, `stage` and `prod`
arrives as an argument from the calling stack in [`../live/`](../live/).

The test is mechanical. If a module cannot produce prod by changing its
arguments alone, prod is not being tested by staging, and the difference will be
discovered on the day it matters.

Empty until `v1-network`, which writes the first one.
