# Pinned Swift source-resolution contract

Status: experimental implementation. This is a read-only source identity
check, separate from document validation and evidence acceptance.

## Input and output

`SourceResolver` accepts a valid passport and an explicit map from authored
repository names to local Git checkout URLs. The CLI requires one or more
`--repository name=/absolute/checkout` arguments. It never guesses a checkout,
fetches a remote, or reads source from the working tree. Revision must be a
full 40- or 64-digit Git object ID whose object type is `commit`. Path must be
relative, without traversal; it must identify a blob in that commit.

The Swift parser indexes nominal types and functions, including declarations
in extensions, by qualified type name and external parameter labels. Exact
examples are `Route`, `Route.evaluate(_:)`, and `Route.evaluate(in:context:)`.
Comments and strings cannot satisfy an anchor. A missing declaration,
duplicate matching declaration, malformed Swift file, unsupported language,
unavailable revision, and unavailable path receive distinct statuses. A
document with no source anchors receives `no_source_anchors`.

Each report entry carries the element ID, anchor index, authored repository,
revision, module, path, symbol, status, and pinned blob object ID when read.
Document validation issues are separate from anchor results. Output order
follows the passport's element and anchor order.

## Meaning of `resolved`

`resolved` establishes one syntactic declaration with that name and external
label sequence in the pinned file. It does **not** establish that the module
field owns the file, that the declaration type-checks or compiles, that a
macro expansion exists, that a test passed, that the code fulfills a SpecGraph
scenario, or that runtime behavior was observed. A source file with parser
errors is not resolved. Conditional compilation branches are indexed together;
if both declare the same symbol the result is ambiguous.

Only ordinary identifier-based Swift type and function symbols are supported
in this slice. Operators, subscripts, initializers, backticked names, generic
specializations, and other languages require later syntax profiles. The
resolver intentionally does not infer coverage from implementation roles,
bindings, names, or passing test suites.

## Repeatable check

`make resolve-zeusus ZEUSUS_CHECKOUT=/absolute/path/to/Zeusus` resolves the
four anchors in the Zeusus route-composition example. CI tests create a
temporary Git repository so they do not depend on a private checkout. Source
resolution remains independent of optional SpecGraph provider locators.
