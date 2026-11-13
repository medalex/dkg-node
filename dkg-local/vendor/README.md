# Vendored ot-node

`ot-node-a8156d6.tar.gz` is the OriginTrail DKG V8 node (`origintrail_node` 8.2.6) at commit
`a8156d63132d5584a8adb8307e046ba45c4e7000` ("Merge pull request #4091 from
OriginTrail/refactor-bdd-tests", 2026-03-27). It is vendored because the upstream repository,
`github.com/OriginTrail/ot-node` (renamed `dkg-engine` in V8.2.1), returns 404 as of 2026-10-20.

Licence: Apache 2.0, see `ot-node/LICENSE` inside the archive. Copyright OriginTrail.

How it was made (the commit is still reachable through the GitHub fork network):

```
git init && git fetch --depth 1 https://github.com/othub-io/ot-node.git a8156d63132d5584a8adb8307e046ba45c4e7000
git archive --format=tar.gz --prefix=ot-node/ -o ot-node-a8156d6.tar.gz FETCH_HEAD
```

sha256: `3700d4da1106475bde95f04fc73634a7136f99e0c57a77cee0ebc6726040ed09`
(checked in `Dockerfile.otnode`).

# Vendored dkg-evm-module

ot-node depends on `git+https://github.com/OriginTrail/dkg-evm-module.git#main`, locked to commit
`1088476e13c3c8b46f087f45cdea103959f2135c` ("Merge pull request #440 from
OriginTrail/new-deployments", 2025-07-09, package version 8.1.0). That repository is gone too, and
the npm release 8.1.0 is a different commit (`0a60162`), so the locked commit is vendored as
`dkg-evm-module-1088476.tgz` and substituted with `npm pkg set` before `npm install`.

Licence: Apache 2.0, `package/LICENSE` inside the archive. Copyright OriginTrail.

How it was made (reachable through the fork `caojeremyv/dkg-evm-module`):

```
git init && git fetch --depth 1 https://github.com/caojeremyv/dkg-evm-module.git 1088476e13c3c8b46f087f45cdea103959f2135c
mkdir src && git archive FETCH_HEAD | tar -x -C src
npm pack ./src --ignore-scripts        # then renamed to dkg-evm-module-1088476.tgz
```

sha256: `570d9d27c97ca7cd1334ac13c6758f5f3c458c460f03324dcff474f787e385b6`.
Contracts, ABI and deploy scripts match `node_modules/dkg-evm-module` of the previously working
image file by file; the archive additionally contains the two `utils/converters/*` binaries.
