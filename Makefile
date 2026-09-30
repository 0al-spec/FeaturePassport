.PHONY: markdown-lint swift-test test validate-example validate-examples validate-zeusus resolve-zeusus

ZEUSUS_CHECKOUT ?= ../../Zeusus

markdown-lint:
	npx --yes markdownlint-cli2 --no-globs AGENTS.md README.md 'docs/**/*.md'

swift-test:
	swift build
	FEATURE_PASSPORT_TEST_CLI="$$(swift build --show-bin-path)/feature-passport" swift test

.PHONY: test-receipt-issuer
test-receipt-issuer:
	swift build
	FEATURE_PASSPORT_TEST_CLI="$$(swift build --show-bin-path)/feature-passport" swift test --filter EvidenceReceiptIssuerTests

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
