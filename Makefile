PROJECT_LIB := $(shell find lib -mindepth 2 -maxdepth 2 -type d)
PROJECT := $(shell echo "$(PROJECT_LIB)" | awk -F '/' '{print $$2 "-" $$3}')
VERSION = $(shell awk --field-separator '"' '/VERSION/ {print $$2}' $(PROJECT_LIB)/version.rb)

.PHONY: patch minor major

patch: _patch _publish

minor: _minor _publish

major: _major _publish

_patch:
	@gem bump -v patch --no-commit

_minor:
	@gem bump -v minor --no-commit

_major:
	@gem bump -v major --no-commit

_publish:
	@bundle install --quiet
	@git commit -am 'Version bump: $(VERSION)'
	@rake release
	@github_changelog_generator --user libis --project $(PROJECT) --token $(CHANGELOG_GITHUB_TOKEN) --no-verbose
	@git commit -am 'Changelog update'
	@git push