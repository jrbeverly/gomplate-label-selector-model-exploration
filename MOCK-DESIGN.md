# Mock Design

## Purpose

This document is a feasibility-first mock design for the metadata-driven templating framework described in `PROBLEM.md`, `TECHNICAL.md`, and `VISION.md`.

Its goal is to answer whether the proposed direction is conceptually workable, what major architectural shape it suggests, and which unresolved decisions still need validation before deeper implementation work begins.

This is intentionally not a detailed implementation spec. It avoids locking the project into exact schemas, storage models, or low-level execution details unless those details materially affect feasibility.

## Executive Summary

The proposed system is fundamentally implementable, but not as "gomplate plus clever templates" alone.

The direction becomes viable if the project is treated as a small metadata interpretation and reconciliation layer that uses `gomplate` as a rendering primitive rather than as the primary place where orchestration logic lives.

In practical terms:

- YAML configuration objects can express declarative intent.
- Labels, annotations, and selectors can drive behavior selection.
- A separate resolution layer can interpret metadata and assemble an execution plan.
- `gomplate` can remain responsible for generic rendering and data expansion.
- Optional transformations that exceed normal template ergonomics will likely need external helpers, plugins, or pre/post-processing stages.

The biggest architectural risk is not technical impossibility. It is accidental complexity caused by hidden behavior, ambiguous selector semantics, and trying to make metadata act like an unbounded programming language.

## Reading of the Source Documents

Across the three source documents, the intended direction appears to be:

- Move behavioral intent out of templates and into configuration metadata.
- Keep templates generic, stable, and reusable across environments and use cases.
- Let labels, annotations, and selectors determine which behaviors apply.
- Borrow the mental model of Kubernetes reconciliation without necessarily reproducing Kubernetes in full.
- Favor long-term extensibility through conventions and generic control logic rather than template forks.

The documents are consistent on the philosophy, but intentionally under-specified on several architectural choices. That is appropriate for an exploration repo, but those gaps now become the main design work.

One document-level ambiguity is worth naming explicitly: `TECHNICAL.md` appears to contain a broken reference token in the "Core Technology" section. This mock design assumes the intended renderer is `gomplate`, based on the repository context and the rest of the source material.

## Design Stance

The most coherent high-level interpretation is:

- `gomplate` is the renderer.
- YAML objects are the source of intent.
- A metadata-aware controller layer decides what should happen.
- Templates should only render already-resolved intent, not discover business behavior on their own.

This boundary is important.

If templates are still expected to inspect labels, evaluate selectors, and coordinate multi-stage behavior directly, the project will recreate the same rigidity it is trying to escape, only in a more indirect form.

If instead selector matching and behavior resolution happen before rendering, the system has a much better chance of remaining understandable and extensible.

## Conceptual Architecture

### 1. Intent Objects

The system should operate on structured YAML objects that contain:

- user-authored configuration payload
- metadata used for behavior selection
- enough identity to support traceability and deterministic output

This does not require adopting the full Kubernetes object model, but it does benefit from a consistent envelope for metadata and object identity.

The important point is not the exact fields. The important point is that behavior-driving metadata must be structurally distinct from the domain payload it influences.

### 2. Behavior Catalog

The system needs an explicit catalog of behaviors that can be activated by metadata.

A behavior in this sense is a high-level unit such as:

- activate a template
- enable an optional transformation stage
- inject additional context
- apply a policy or normalization rule
- trigger a post-processing step

This catalog is the missing conceptual bridge between "metadata exists" and "the system knows what to do."

Without a behavior catalog, labels and annotations are just strings. With one, they become selectors for reusable capabilities.

### 3. Selector and Resolution Layer

The selector and resolution layer should:

- normalize input metadata
- evaluate which behaviors apply to which objects
- resolve precedence and conflicts
- produce a deterministic execution plan
- expose why each decision was made

This is the true heart of the system.

It is also the layer that should own reconciliation-style logic. In this context, "reconciliation" should initially mean repeated, deterministic convergence from declarative input to rendered output, not necessarily a long-running distributed controller.

### 4. Rendering Layer

The rendering layer should use `gomplate` as a reusable output primitive.

Its responsibilities should be narrow:

- render templates using resolved context
- compose shared template fragments
- access supported datasources where appropriate
- call bounded helper functions or plugins when rendering alone is insufficient

This preserves the original goal of keeping templates generic and minimizing embedded business logic.

### 5. Transformation and Extension Layer

Some behavior will likely not fit cleanly into plain template rendering.

Examples include:

- non-trivial normalization
- cross-object aggregation
- advanced selector evaluation
- policy validation
- content transformations that are awkward in templating syntax

Those concerns should live in explicit extension points outside templates. The exact mechanism can stay open for now, but the architecture should assume such an extension layer will exist.

### 6. Output and State Boundary

The system needs a clear definition of what it reconciles toward.

Possible interpretations include:

- rendered files in a local output directory
- generated configuration bundles
- derived artifacts for downstream tools
- a dry-run plan and explanation report

The design is much more tractable if the first target is generated artifacts on disk rather than direct mutation of external systems.

## End-to-End Workflow

A viable high-level workflow would look like this:

1. Load YAML intent objects and any shared behavior definitions.
2. Normalize metadata into a predictable internal view.
3. Evaluate selectors and determine which behaviors apply.
4. Resolve ordering, precedence, and conflicts.
5. Build a resolved per-object or per-group execution context.
6. Invoke `gomplate` templates and any approved helper stages.
7. Emit artifacts and an explanation of what happened.
8. Optionally repeat this loop on source changes to approximate reconciliation.

This sequence preserves declarative intent while keeping orchestration logic out of templates.

## Why This Is Viable

The proposal is viable because its parts fit together naturally when the responsibilities are separated:

- YAML is a good format for structured declarative input.
- labels, annotations, and selectors are proven concepts for metadata-driven applicability
- `gomplate` is well-suited to generic text rendering with structured data inputs
- a lightweight controller can interpret metadata and prepare render contexts
- reconciliation can start as an idempotent local compile loop before becoming anything more operational

Nothing in the desired model requires a full platform or distributed system. The core idea can be prototyped as a local engine that repeatedly transforms intent objects into deterministic outputs.

## Main Architectural Concerns

### Hidden Control Flow

If metadata can activate many implicit behaviors, users may lose the ability to understand why output changed.

The system will need strong explainability from the beginning:

- why a behavior applied
- which selector matched
- what precedence rule won
- which templates or transforms activated

Without that, the design becomes "magic configuration," which is hard to debug and easy to mistrust.

### Selector Scope Creep

Selector languages tend to expand quickly.

If the system starts with simple presence and equality matching but grows into rich query semantics, it may become a rule engine that is harder to reason about than the templates it replaced.

The project should validate whether it really needs:

- object-local matching only
- cross-object matching
- set-based and negative matching
- inheritance or composition across selector scopes

That decision materially affects complexity.

### Reconciliation Ambiguity

The source docs use reconciliation language, but the operational meaning is still unclear.

There is a major difference between:

- rerun the engine when inputs change

and:

- continuously observe real-world state and converge external systems

The first is very feasible for this project. The second is a much larger product category.

### Metadata Becoming a Programming Language

The design aims to avoid procedural logic in templates, but the same logic can simply reappear as increasingly clever metadata conventions.

That trade only helps if behavior remains:

- constrained
- discoverable
- deterministic
- documented

If annotations become a grab bag of implicit commands, the system will gain abstraction but lose clarity.

### Behavior Composition and Conflict Resolution

The moment multiple labels or selectors activate multiple behaviors, composition rules matter.

The design needs a stable answer to questions like:

- can multiple behaviors apply to one object
- can behaviors additively compose
- what happens when two behaviors want incompatible outputs
- do annotations override labels
- can one behavior disable another

This is a core design decision, not an implementation detail.

### Gomplate Ergonomics Ceiling

`gomplate` is strong as a renderer, but not ideal as the sole home for orchestration, graph reasoning, or rich policy logic.

That is not a deal-breaker. It simply means the architecture should not force `gomplate` to be the controller.

## Unresolved Decisions That Block Clean Progress

These are the main questions that should be answered before the project commits to a deeper implementation path:

- What is the canonical unit of intent: one object, a document set, or a directory-level bundle?
- What is the minimum object envelope needed for metadata, identity, and payload separation?
- What exactly can selectors target: labels only, annotations too, payload fields, or relationships between objects?
- Are behaviors attached directly to templates, or do templates stay downstream from a separate behavior catalog?
- Is the primary execution model batch rendering, watch-mode local reconciliation, or something more controller-like?
- What is the target output boundary: files, bundles, reports, or external systems?
- How are multiple matching behaviors composed and ordered?
- What degree of extension is acceptable through plugins or helper programs?
- Who is expected to author new behaviors: template authors, platform maintainers, or configuration authors?
- What observability is required so users can trust the system?

## Clarifying Questions

These are the questions I would ask before treating the design as settled:

1. Is the intended outcome primarily "generate files from intent" or "manage a broader lifecycle with ongoing convergence"?
2. Should the system support reasoning across multiple YAML objects, or should behavior selection remain object-local at first?
3. Do you want labels and annotations to be purely triggers, or can they also carry parameters and overrides?
4. Is there an expected shared metadata envelope already in mind, or is that still completely open?
5. Should new behaviors be introduced mainly by adding controller logic, by adding reusable rule definitions, or by adding templates plus metadata conventions together?
6. How important is human-readable explain output in the first prototype?
7. Are there specific downstream artifact types that matter most for the exploration?
8. Is "reconciliation" meant literally as a loop with observed state, or more loosely as deterministic re-rendering from desired input?

## Proposed Repository Shape

The repository can stay lightweight while still reflecting the architectural boundaries above.

```text
/
|- PROBLEM.md
|- TECHNICAL.md
|- VISION.md
|- MOCK-DESIGN.md
|- docs/
|  |- decisions/
|  |- concepts/
|- examples/
|  |- intents/
|  |- rendered/
|- templates/
|  |- base/
|  |- partials/
|- behaviors/
|  |- selectors/
|  |- rules/
|- engine/
|  |- loader/
|  |- resolver/
|  |- renderer/
|  |- explain/
|- plugins/
|- testdata/
|  |- golden/
```

This layout is only conceptual. Its purpose is to separate intent, behavior definition, engine logic, rendering assets, and validation artifacts.

## Recommended Validation Path

The next step should not be a full implementation. It should be a small proof of conceptual coherence.

Suggested validation sequence:

1. Define a tiny intent envelope and a very small metadata vocabulary.
2. Create a minimal behavior catalog with a few examples of label, annotation, and selector activation.
3. Build a resolver that outputs an explainable execution plan before it renders anything.
4. Render a few outputs through `gomplate` using only resolved context.
5. Measure whether templates stayed simpler than they would have been otherwise.
6. Test at least one awkward behavior that likely needs an extension point.
7. Decide whether the reconciliation story should remain batch-oriented or grow into watch-mode.

If those steps work, the architecture is not just plausible. It is on a credible path.

## Recommendation

Proceed with the exploration.

The concept is strong enough to justify prototyping, but the prototype should be designed around one central rule:

Templates render.
Metadata selects.
A resolver reconciles.

If that separation holds, the system has a real chance to become the lightweight declarative framework described in the source documents.

If that separation collapses, the project will likely reproduce the original problem under new terminology.
