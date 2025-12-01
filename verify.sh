#!/bin/sh
set -u
cd "$(dirname "$0")" || exit 1

V=.work/verify
LOCAL=behaviors.yaml
FULL="behaviors.yaml behaviors-beyond-template.yaml"

fails=0
RUN=canonical

check() { desc=$1; shift; if "$@" >/dev/null 2>&1; then echo "ok   $desc"; else echo "FAIL $desc"; fails=$((fails + 1)); fi; }
refute() { desc=$1; shift; if "$@" >/dev/null 2>&1; then echo "FAIL $desc"; fails=$((fails + 1)); else echo "ok   $desc"; fi; }

# run <name> <intents> <templates-dir> <catalogs...>
run() {
	n=$1
	i=$2
	t=$3
	shift 3
	ROOT="$V/$n" INTENTS="$i" TEMPLATES="$t" sh build.sh "$@" || exit 1
}

conf() { grep -q "$2" "$V/$RUN/out/$1.conf"; }
resolved() { jq -e "$2" "$V/$RUN/.work/$1-resolved.json"; }
activated() { behavior "$1" "$2" .activated; }
behavior() { # behavior <object> <name> <jq filter over that behavior's record>
	jq -e --arg b "$2" ".explain[]|select(.behavior==\$b)|$3" "$V/$RUN/.work/$1-resolved.json"
}
mono() { gomplate --file templates/monolithic.tmpl --context ".=$V/$1/.work/$2-raw.json"; }
count() { pat=$1; shift; cat "$@" | grep -oE "$pat" | wc -l; }

digest_ok() {
	sum=$(sed '/^# digest: /,$d' "$1" | sha256sum | cut -c1-16)
	tail -1 "$1" | grep -q "sha256:$sum\$"
}
only_resolver() { grep -q "$1" "$V/canonical/out/atlas.conf" && ! grep -q "$1" "$V/mono-canonical.conf"; }
names_both() { grep -q rival-limits "$1" && grep -q production-limits "$1"; }

rm -rf "$V"
mkdir -p "$V"

# Scenarios that do not vary the inputs all read one canonical run.
run canonical examples/intents.yaml templates $FULL

echo
echo "[selector operator matrix]"
check "Equals: production-limits matches atlas (env=production)" activated atlas production-limits
refute "Equals: production-limits skips cipher (env=staging)" activated cipher production-limits
check "In: tier In [web] matches beacon" activated beacon production-web-ratelimit
refute "In: tier In [web] skips cipher (tier=api)" activated cipher production-web-ratelimit
check "Exists: managed label present on atlas" activated atlas managed-baseline
refute "Exists: managed label absent on delta" activated delta managed-baseline
check "DoesNotExist: matches delta, which has no managed label" activated delta unmanaged-warning
refute "DoesNotExist: skips atlas, which has the label" activated atlas unmanaged-warning
check "Gt: spec.workers 8 > 4 matches echo" activated echo high-worker-tuning
refute "Gt: spec.workers 4 > 4 is false for atlas" activated atlas high-worker-tuning
check "empty selector matches every object" activated delta baseline-limits

echo
echo "[annotations carry parameters, labels only select]"
check "atlas scrape interval taken from its annotation" conf atlas "scrape_interval: 15s"
check "echo scrape interval taken from its annotation" conf echo "scrape_interval: 60s"
check "atlas metrics path taken from its annotation" conf atlas "endpoint: /healthz/metrics"
check "beacon falls back to the declared default path" conf beacon "endpoint: /metrics"
check "cipher TLS version overridden by annotation" conf cipher "min_version: TLSv1.2"
check "atlas TLS version falls back to the declared default" conf atlas "min_version: TLSv1.3"
check "a contribution is a gomplate expression over the object" \
	resolved atlas '.fragments.tls.cert=="/etc/certs/atlas.pem"'

echo
echo "[priority override and deep merge]"
check "atlas limits merge: timeout from production-limits, retries from baseline-limits" \
	resolved atlas '.context.limits=={"timeout":"5s","retries":"1"}'
check "cipher keeps both baseline values (production-limits did not match)" \
	resolved cipher '.context.limits=={"timeout":"30s","retries":"1"}'
check "explain records baseline-limits.timeout as suppressed" \
	behavior atlas baseline-limits \
	'[.writes[]|select(.action=="suppressed")]|length==1 and .[0].path=="limits.timeout"'
check "explain names production-limits as the winning writer" \
	behavior atlas baseline-limits '.writes[]|select(.action=="suppressed")|.by=="production-limits"'

echo
echo "[one behavior disabling another]"
refute "echo renders no rate_limit block" conf echo "rate_limit"
check "atlas still renders rate_limit" conf atlas "rate_limit"
check "echo records the exemption that caused it" conf echo "ratelimit: true"
check "explain shows production-web-ratelimit matched echo but did not activate" \
	behavior echo production-web-ratelimit '.matched and (.activated|not)'
check "explain names the disabling behavior" \
	behavior echo production-web-ratelimit '.disabled_by=="ratelimit-exemption"'

echo
echo "[cross-object aggregation, in the template]"
check "atlas pool lists every edge member" \
	resolved atlas '[.fragments.pool.members[].name]==["atlas","beacon","echo"]'
check "cipher pool lists every internal member" \
	resolved cipher '[.fragments.pool.members[].name]==["cipher","delta"]'
check "sibling object appears in atlas rendered output" conf atlas "host: beacon"
check "explain records group key and membership" \
	behavior atlas pool-membership '.group.key=="edge" and .group.members==["atlas","beacon","echo"]'

# An edit to one object must change a different object's output.
sed '/name: beacon/,/^$/ s/pool: "edge"/pool: "internal"/' examples/intents.yaml >"$V/moved.yaml"
run moved "$V/moved.yaml" templates $FULL
RUN=moved
refute "moving beacon removes it from the atlas output" conf atlas "host: beacon"
check "moving beacon adds it to the cipher output" conf cipher "host: beacon"
refute "an untouched object's output changes when a sibling moves" \
	cmp -s "$V/canonical/out/delta.conf" "$V/moved/out/delta.conf"
RUN=canonical

echo
echo "[policy diagnostics]"
check "port collision reported on cipher" conf cipher "port 9000 shared inside pool internal by cipher, delta"
check "port collision reported on delta" conf delta "port 9000 shared inside pool internal by cipher, delta"
refute "atlas reports no port collision" conf atlas "unique-ports"
check "delta reports the unmanaged warning" conf delta "require-managed"
check "delta carries both diagnostics" resolved delta '.diagnostics|length==2'

sed '/name: delta/,/^$/ s/port: 9000/port: 9001/' examples/intents.yaml >"$V/repaired.yaml"
run repaired "$V/repaired.yaml" templates $FULL
RUN=repaired
refute "collision clears once the port is changed" conf cipher "unique-ports"
RUN=canonical

echo
echo "[postprocess stage, applied by the driver]"
check "rendered output ends with a digest footer" \
	grep -q "^# digest: sha256:" "$V/canonical/out/atlas.conf"
check "digest is a hash of the body above it" digest_ok "$V/canonical/out/atlas.conf"

echo
echo "[NotIn semantics on a missing key]"
run notin examples/intents.yaml templates $FULL fixtures/notin-probe.yaml
RUN=notin
check "NotIn matches an object missing the key entirely (beacon)" activated beacon zz-notin-probe
refute "NotIn skips an object whose value is in the set (atlas)" activated atlas zz-notin-probe
RUN=canonical

echo
echo "[equal-priority conflict is fatal]"
ROOT="$V/conflict" sh build.sh $FULL fixtures/rival-limits.yaml >/dev/null 2>"$V/conflict.err"
rc=$?
check "the resolver template aborts on an equal-priority write to the same leaf" test "$rc" -ne 0
check "conflict message names the contested path" grep -q "limits.timeout" "$V/conflict.err"
check "conflict message names both competing behaviors" names_both "$V/conflict.err"

echo
echo "[counterfactual: resolver template vs monolithic template]"
run local examples/intents.yaml templates $LOCAL
for n in atlas beacon cipher delta echo; do
	mono local "$n" >"$V/mono-$n.conf"
	check "byte-identical output from both paths: $n" cmp -s "$V/mono-$n.conf" "$V/local/out/$n.conf"
done

GENERIC="templates/service.tmpl templates/partials/canary.tmpl templates/partials/metrics.tmpl"
GENERIC="$GENERIC templates/partials/pool.tmpl templates/partials/ratelimit.tmpl templates/partials/tls.tmpl"
META='\.labels|\.annotations'
BRANCH='\{\{-?[[:space:]]*(if|else)\b'
g_inspect=$(count "$META" $GENERIC)
m_inspect=$(count "$META" templates/monolithic.tmpl)
g_branch=$(count "$BRANCH" $GENERIC)
m_branch=$(count "$BRANCH" templates/monolithic.tmpl)
r_branch=$(count "$BRANCH" templates/resolve.tmpl)
g_lines=$(cat $GENERIC | awk 'END{print NR}')
m_lines=$(awk 'END{print NR}' templates/monolithic.tmpl)
r_lines=$(awk 'END{print NR}' templates/resolve.tmpl)

check "render templates never reference labels or annotations" test "$g_inspect" -eq 0
check "monolithic template must reference labels and annotations directly" test "$m_inspect" -gt 0
echo "     render templates: $g_lines lines, $g_branch branches, $g_inspect metadata inspections"
echo "     monolithic:       $m_lines lines, $m_branch branches, $m_inspect metadata inspections"
echo "     resolve.tmpl:     $r_lines lines, $r_branch branches (the selection moved here, it did not vanish)"

echo
echo "[cost of adding a behavior to each path]"
run audit examples/intents.yaml templates $LOCAL fixtures/audit-trail.yaml
RUN=audit
mono audit atlas >"$V/mono-audit.conf"
check "context behavior: atlas gains an audit block" conf atlas "sink: s3://audit/atlas"
refute "context behavior: cipher is unaffected" conf cipher "audit"
refute "context behavior: monolithic path diverges without a template edit" \
	cmp -s "$V/mono-audit.conf" "$V/audit/out/atlas.conf"

cp -r templates "$V/tracing-templates"
cp fixtures/tracing.tmpl "$V/tracing-templates/partials/tracing.tmpl"
run tracing examples/intents.yaml "$V/tracing-templates" $LOCAL fixtures/tracing-export.yaml
RUN=tracing
mono tracing atlas >"$V/mono-tracing.conf"
check "partial behavior: atlas gains a tracing block" conf atlas "endpoint: otlp://collector:4317"
refute "partial behavior: cipher has no metrics annotation and is unaffected" conf cipher "tracing"
check "partial behavior: render templates unchanged despite a new output shape" \
	cmp -s "$V/tracing-templates/service.tmpl" templates/service.tmpl
check "partial behavior: the resolver template is unchanged too" \
	cmp -s "$V/tracing-templates/resolve.tmpl" templates/resolve.tmpl
refute "partial behavior: monolithic path cannot gain it without an edit" \
	grep -q tracing "$V/mono-tracing.conf"
check "new partial slots into priority order without touching existing partials" \
	resolved atlas '.partials==["canary","tracing","ratelimit","metrics","tls"]'
RUN=canonical

echo
echo "[what still needs the driver]"
mono canonical atlas >"$V/mono-canonical.conf"
check "pool membership reaches siblings, which a per-object template cannot" only_resolver upstream_pool
check "the digest is the one stage outside gomplate: it hashes finished output" only_resolver "^# digest:"
check "canary arithmetic is gomplate's own math, not the driver's" conf atlas "weight: 90"

echo
if [ "$fails" -eq 0 ]; then
	echo "all checks passed"
else
	echo "$fails check(s) failed"
	exit 1
fi
