# Running Discourse's test suite in a Claude Code cloud container

What it took to run this plugin's specs (request, model, Workflows node and system specs)
against Discourse `main` in an Ubuntu 24.04 cloud session, October 2026. Only
`integrated_verification` needs it; it gives one Discourse target (`main`), not the release
matrix.

Work in the session scratchpad, never inside the plugin checkout.

## 1. Discourse core

```sh
git clone --depth 1 https://github.com/discourse/discourse.git core
ln -sfn /path/to/discourse-ballotage-nautas core/plugins/discourse-ballotage-nautas
```

## 2. Ruby 3.4

Core needs Ruby `~> 3.4`; the image ships 3.3. The proxy blocks `cache.ruby-lang.org` and
GitHub release tarballs, but git clones work, so build from the tag:

```sh
git clone --depth 1 --branch v3_4_9 https://github.com/ruby/ruby.git rubysrc
cd rubysrc && ./autogen.sh
./configure --prefix=/opt/rbenv/versions/3.4.9 --disable-install-doc \
  --with-baseruby=/opt/rbenv/versions/3.3.6/bin/ruby
make -j4 && make install
export PATH=/opt/rbenv/versions/3.4.9/bin:$PATH   # RBENV_VERSION is not enough
gem install bundler
```

## 3. System packages

```sh
apt-get install -y postgresql-server-dev-16 libpq-dev imagemagick fonts-urw-base35
# pgvector from apt is 0.6 and lacks halfvec, which discourse-ai's schema needs:
git clone --depth 1 --branch v0.8.0 https://github.com/pgvector/pgvector.git
(cd pgvector && make && make install)
# Discourse calls ImageMagick 7's `magick`; Ubuntu ships 6:
printf '#!/bin/sh\nexec convert "$@"\n' > /usr/local/bin/magick && chmod +x /usr/local/bin/magick
service postgresql start && service redis-server start
su postgres -c "psql -c 'CREATE ROLE root SUPERUSER LOGIN'"
```

## 4. Dependencies and database

```sh
cd core
bundle install && pnpm install --frozen-lockfile
RAILS_ENV=test LOAD_PLUGINS=1 bin/rake db:create db:migrate
```

## 5. Specs

```sh
LOAD_PLUGINS=1 bin/rspec plugins/discourse-ballotage-nautas/spec --exclude-pattern "**/system/**"
```

System specs also need the compiled frontend **and** compiled plugin bundles — without the
second step every plugin route 404s in the browser:

```sh
LOAD_PLUGINS=1 bin/ember-cli --build
RAILS_ENV=test LOAD_PLUGINS=1 bin/rake assets:precompile:build_plugins   # rerun after JS changes
# Playwright wants a newer Chromium build than the preinstalled one; point it there:
mkdir -p /opt/pw-browsers/chromium-1234
ln -sfn /opt/pw-browsers/chromium-1194/chrome-linux /opt/pw-browsers/chromium-1234/chrome-linux64
touch /opt/pw-browsers/chromium-1234/{INSTALLATION_COMPLETE,DEPENDENCIES_VALIDATED}
LOAD_PLUGINS=1 bin/rspec plugins/discourse-ballotage-nautas/spec/system
```

Adjust the Chromium revision to whatever the Playwright error names.

## 6. Plugin linters (run in the plugin checkout)

```sh
bundle install && pnpm install
export LANG=C.UTF-8      # syntax_tree fails on non-ASCII files otherwise
bundle exec ruby $(bundle show rubocop)/exe/rubocop
bundle exec ruby $(bundle show syntax_tree)/exe/stree check Gemfile $(git ls-files '*.rb')
pnpm lint:js && pnpm lint:prettier
```
