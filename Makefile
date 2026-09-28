.PHONY: markdown-lint swift-test test validate-example validate-examples validate-zeusus resolve-zeusus

ZEUSUS_CHECKOUT ?= ../../Zeusus

markdown-lint:
	npx --yes markdownlint-cli2 --no-globs AGENTS.md README.md 'docs/**/*.md'

swift-test:
	swift test

test: swift-test markdown-lint validate-examples

validate-example: validate-examples

validate-examples:
	swift run feature-passport validate examples/local-passport.json
	swift run feature-passport validate examples/invoice-passport-schema-fixture.json
	$(MAKE) validate-zeusus

validate-zeusus:
	swift run feature-passport validate examples/zeusus-route-composition.json

resolve-zeusus:
	swift run feature-passport resolve-sources examples/zeusus-route-composition.json --repository zeusus=$(abspath $(ZEUSUS_CHECKOUT))
