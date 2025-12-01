# gomplate-label-selector-model-exploration

> [!WARNING]
> **AI-authored:** This change was autonomously planned and implemented by an AI software factory from a human-authored specification, with possible subsequent human review or modification.

Label- and annotation-driven templating done inside gomplate: `templates/resolve.tmpl` evaluates a behavior catalog against YAML intent objects and emits a resolved document, which the render templates consume. A second, monolithic template reproduces the same output by branching on raw metadata itself, so the cost of each approach can be compared rather than asserted.

`build.sh` only orchestrates — it invokes gomplate and appends the digest, which is the one stage a template cannot perform on its own.

`behaviors.yaml` holds the object-local catalog; `behaviors-beyond-template.yaml` holds the three a per-object template cannot express. Catalogs are plain lists, so they concatenate, and the counterfactual is just the first file on its own.

```sh
sh build.sh
sh verify.sh

sh build.sh behaviors.yaml
```

## Notes

- AI factory produced this a couple of times; generally effective at moving work forward.
- Repeatedly defaulted to simpler Python implementations instead of the intended Go-template design.
- Multiple nudges toward the intended architecture did not initially change the implementation direction.
- Eventually converged on the intended outcome through factory iteration plus manual intervention.
- Main gap: implementation can drift toward the model’s preferred/simple solution rather than preserve architectural intent.
- Final design became somewhat more complicated than intended, but still within a reasonable level.
- Core concept was simple: dependency-injection/plugin-style behaviour inside the templating system.
- Goal was to keep individual components simple while allowing behaviour to be injected/composed.
- Additional high-level context did not materially help: mock design, problem statement, technical vision, specification, related docs.
- For novel concepts, reference implementations or pseudocode likely communicate intent better than more prose.
- Model showed passive resistance to unfamiliar architecture by repeatedly falling back to a conventional implementation.
- Novel design patterns likely need more illustrative examples to prevent fallback to “reasonable default” implementations.
- Future factory inputs should favour concrete examples alongside specifications when architectural intent is non-obvious.
