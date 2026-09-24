# Contributing

Thanks for helping. The most valuable contributions are **fixes to site
profiles** (when a judge adds a new CDN or captcha) and **new entries for
the AI denylist / blocked apps**.

## Quick orientation

- The code is plain Bash, one module per concern in `lib/`, and the
  dispatcher is `bin/cmanager`. Start with [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- Configuration defaults live in `config/`. `install.sh` copies them to `/etc/contest-env/`.
- Tests are in `tests/run.sh`. They don't need root, but as root they also
  validate the generated nftables ruleset and Squid config.

```bash
make lint     # shellcheck (must be clean)
make test     # unit tests
sudo make test
```

CI runs all three on every push and pull request.

## Fixing or adding a site profile

1. Reproduce: in a lab with contest mode on, log in, open a problem and
   submit, then run `sudo cmanager denied`.
2. Add only hosts the site **needs** (its own CDN, images, captcha, formula
   renderer). Never add analytics, ads, search engines, code hosting, social
   networks or anything AI.
3. Edit `config/sites/<judge>.txt`. The first comment line is the
   description; each entry gets a short comment saying why it is needed:

   ```text
   # AtCoder
   atcoder.jp                   # includes img.atcoder.jp
   @common
   ```

4. Run `make test`. It fails if a profile contains an invalid domain, an AI
   domain or a risky domain.
5. In the pull request, say which page broke without the change and how
   you tested it.

## Adding AI services or programs

- AI websites/APIs: add the registrable domain to `config/ai-denylist.txt`,
  in the right section. Sub-domains are covered automatically.
- AI programs: add the command name and the install directory to
  `config/blocked-apps.txt`.

## Code changes

- Keep modules focused. New behaviour that `restrict` applies needs a
  matching undo in `unrestrict`.
- Every generated file must be validated before it is activated (see
  `cm_fw_apply` → `nft -c`, and `cm_proxy_render` → `squid -k parse`).
- Never prompt in a code path that can run unattended (`unrestrict`,
  `reset --force`, the guard).
- Update the relevant page in `docs/` and add a line to `CHANGELOG.md`.

## Reporting a bypass

If you find a way for the contest account to reach a non-allowlisted site
or run an AI tool, please **don't** post the details publicly before a fix
exists. Contact the maintainers first (open an issue that only says
"security report, please contact me").
