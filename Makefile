.PHONY: markdown-lint swift-test test validate-example

markdown-lint:
	npx --yes markdownlint-cli2 --no-globs AGENTS.md README.md 'docs/**/*.md'

swift-test:
	swift test

test: swift-test markdown-lint

validate-example:
	swift run feature-passport validate examples/local-passport.json
