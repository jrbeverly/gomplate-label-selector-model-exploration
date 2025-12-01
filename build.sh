#!/bin/sh
# Driver. Everything decided here is orchestration; all resolution happens in
# templates/resolve.tmpl. The digest is the one stage a template cannot do,
# because it hashes the output that rendering has not finished producing yet.
set -eu
cd "$(dirname "$0")"

INTENTS=${INTENTS:-examples/intents.yaml}
TEMPLATES=${TEMPLATES:-templates}
ROOT=${ROOT:-.}
[ "$#" -gt 0 ] || set -- behaviors.yaml behaviors-beyond-template.yaml

WORK=$ROOT/.work
OUT=$ROOT/out
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"

# Catalogs are plain lists, so several concatenate into one.
cat "$@" >"$WORK/catalog.yaml"

names=$(gomplate -d i="$INTENTS" -i '{{ range (ds "i").services }}{{ .name }} {{ end }}')

for n in $names; do
	SERVICE=$n gomplate -d i="$INTENTS" -d b="$WORK/catalog.yaml" \
		-f "$TEMPLATES/resolve.tmpl" >"$WORK/$n-resolved.json"
	SERVICE=$n gomplate -d i="$INTENTS" \
		-i '{{ range (ds "i").services }}{{ if eq .name (getenv "SERVICE") }}{{ . | data.ToJSONPretty "  " }}{{ end }}{{ end }}' \
		>"$WORK/$n-raw.json"
	gomplate --context ".=$WORK/$n-resolved.json" --template "partials=$TEMPLATES/partials/" \
		-f "$TEMPLATES/service.tmpl" >"$OUT/$n.conf"

	for step in $(gomplate --context ".=$WORK/$n-resolved.json" -i '{{ range .postprocess }}{{ . }} {{ end }}'); do
		case $step in
		sha256-footer)
			printf '# digest: sha256:%s\n' \
				"$(sha256sum "$OUT/$n.conf" | cut -c1-16)" >>"$OUT/$n.conf"
			;;
		*)
			echo "unknown postprocess step: $step" >&2
			exit 1
			;;
		esac
	done
done
