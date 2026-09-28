.PHONY: markdown-lint swift-test test validate-example validate-examples

markdown-lint:
	npx --yes markdownlint-cli2 --no-globs AGENTS.md README.md 'docs/**/*.md'

swift-test:
	swift test

test: swift-test markdown-lint validate-examples

validate-example: validate-examples

validate-examples:
	swift run feature-passport validate examples/local-passport.json
	swift run feature-passport validate examples/invoice-passport-schema-fixture.json
