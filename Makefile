.PHONY: markdown-lint

markdown-lint:
	npx --yes markdownlint-cli2 "**/*.md"
