# sparrow-reduce

The script, `make-criteria.py` makes a fresh script (`criteria.sh`) that is required for Creduce.
More precisely, `criteria.sh` computes so-called [interestingness test](http://embed.cs.utah.edu/creduce/using/).
The template only checks naive logic i.e. compilation and sparrow's Clang frontend check.
Note that one may tweak the script or add custom logic to reduce in terms of specific behavior. (e.g. `grep`, `diff`, ..)
For your information, refer to the last section, [Misc: Custom Logic](##misc:-custom-logic)

## Install

Install [Sparrow](https://github.com/prosyslab/sparrow) and [Creduce](https://github.com/csmith-project/creduce).
Make sure they are added to `$PATH` variable so that can be executed everywhere.
This is required since Creduce works in `/tmp` directory.
If you are working on **elvis01** machine, just install Sparrow. (Creduce is already there for you)

## Run

```sh
$ ./make-criteria.py <PATH_TO_TARGET_FILE>
# If success, `criteria.sh` is generated at <PATH_TO_TARGET_FILE>
```

Indeed, one may run the script (`make-criteria.sh`) everywhere, not specifically at the project's root directory.

## Example

```sh
# Assume tar.c is located in ~workspace/test-bed
$ ./make-criteria.py path/to/target
# cd to where the target file is located
$ cd path/to
# Note that `criteria.sh` is generated
$ creduce criteria.sh target
```

## Misc: Custom Logic

The following script assumes that the error message `Fatal error: exception (Invalid_argument "option is None")` from `sparrow` is interesting.

```sh
#!/usr/bin/env bash

clang 002.cookies.o.i >/dev/null 2>&1 &&\
! sparrow -il -frontend clang 002.cookies.o.i >out.txt 2>&1 &&\
grep 'Fatal error: exception (Invalid_argument "option is None")' out.txt
```
