---
name: explain-structure
description: Explain a sizable or complex structure overview-first — one diagram, then chapters, then detail. Use this when someone asks how a system, codebase, architecture, request or data flow, state machine, dependency graph, or pipeline is put together, and the subject spans roughly eight or more elements or crosses a layer, process, service, or repository boundary — including phrasings like "how does X work", "walk me through", "どこを通ってる", "構成を説明して", "依存関係を教えて". Use it even when no diagram was asked for. Do not use it to define a term or a concept, to answer a single-fact lookup, or to describe a handful of files that a few sentences already cover.
---

# Explain Structure

Prose serializes a structure that the reader then has to rebuild in their head. A diagram hands them the structure directly, which frees the text to carry only what a picture cannot: why a boundary sits where it does, what breaks first, which assumption is load-bearing.

The failure this skill exists to prevent is a flood of undifferentiated prose with no overview and no picture.

## When this applies

Two conditions, both required.

1. **The subject is an actual structure** — a codebase, a service topology, a request or data flow, a state machine, a dependency graph, a pipeline, a build or release path.
2. **It is too big to hold at once** — roughly eight or more elements, or it crosses a boundary between layers, processes, services, or repositories.

Do not load this skill for:

- **A term or a concept.** "What is a prop AMM?" wants a mechanism explained in prose. A box labelled with the term teaches nothing the sentence did not. Route that to `evidence-work`'s specialist-explanation mode.
- **A single-fact lookup.** A path, a value, a yes or no. Answer it in one line.
- **A small structure.** Measured against a five-file, three-layer example, an unaided answer already produced the dependency direction, the inversion boundary, a responsibility table, and `file:line` citations. Below the threshold this skill adds length, not clarity — which is the opposite of its purpose.

Above the threshold the gate still applies, in the strong form both Google and the artifact-diagramming guidance use: draw a figure only for information that is otherwise hard to express in words. If a sentence says it faster, write the sentence.

Two neighbouring concerns stay separate from this one:

- **Evidence.** Shape is not sufficiency. When accuracy depends on current sources, a named target, or the user's own constraints, run `evidence-work` alongside this skill.
- **Genre.** An explanation is understanding-oriented; it opens a topic up for consideration rather than instructing. Keep step-by-step procedure and exhaustive reference material out of it, because an explanation that absorbs them buries both. Offering alternatives and counter-examples is explanation's job, not a digression from it.

## Calibrate to the reader first

Decide who the explanation is for and what it assumes they already know, and say what it does not cover. An unbounded explanation is the flood.

This changes the answer rather than decorating it. Scaffolding that helps a newcomer measurably _hurts_ an expert — the expertise-reversal effect, and in the original wiring-diagram studies the diagram-alone condition overtook diagram-plus-text once learners became fluent. For a reader who already knows the codebase, the diagram plus terse anchors beats the same diagram plus a prose walkthrough. For a newcomer the walkthrough earns its place, so do not apply the prose budget below as if every reader were an expert.

## The shape

1. **Overview** — one diagram, its caption, and at most two or three sentences naming the parts and the single claim the picture makes.
2. **Chapter outline** — only when the explanation is long enough that the reader needs to navigate it. A roadmap serves a long document; on a short answer it is a redundant layer.
3. **Detail** — one section per part, ordered along the flow in the diagram rather than alphabetically or by file size.

Treat this as a default, not a formula. Diátaxis says exactly that about its own model, and a rigidly enforced answer-first structure flattens genuinely exploratory material. Depart when the material demands it and give the reason in a line. Never depart by starting from the details.

## What to draw

- **Draw the mechanism, not the names.** A box labelled `cache` says less than the sentence it replaced. Draw the path a request takes through it, the two stores it sits between, and the arrow that disappears when you remove it.
- **Hold one level of abstraction per diagram.** Mixing a class, a deployment unit, and a business area into one picture is the most reliable way to make an architecture diagram unreadable.
- **Label every arrow with the intent of the relationship, and keep the label consistent with the arrow's direction.** `writes`, `invalidates`, `polls every 30s` is information; a bare arrow only says "related somehow".
- **When comparing options, draw the difference** — before and after, or the single edge each option adds or removes. Two labelled boxes side by side with nothing connecting them to the system is a restated option list, not a comparison.
- **Name each boundary and say what crosses it**: process, layer, package, deployment unit, trust boundary. Put the protocol and the credential on the crossing itself.
- **Use the real identifiers from the code**, so the reader can grep for them. Read the code to get them.
- **Never invent an edge, a label, or a component to round the picture out.** A gap you flag is worth more than a plausible fabrication.
- **Keep the diagram's words on the diagram.** Text the reader must hold against the picture belongs on the picture; pulling it out into separate prose measurably slows comprehension. Short labels and a caption are not the redundancy the prose budget warns about — they help.

## Self-check before shipping a diagram

Adapted from the C4 model's diagram review checklist. It takes seconds and catches most of what makes a generated diagram useless.

- Does it carry a title or caption stating what it shows and how far its scope reaches?
- Does every element have a name, and can the reader tell what kind of thing it is and what it does?
- Is every acronym in it understandable without outside knowledge?
- Does every arrow carry an intent label that agrees with its direction?
- Where shape, line style, or colour carries meaning, is that meaning stated on the mark or in a key?
- Could a reader who found this figure on its own still read it?

Write the caption first, then build the diagram to match it. If the caption will not fit in one sentence, the diagram is trying to make more than one claim.

## Size and splitting

No node-count law survives contact with the evidence, so treat these as heuristics and know where each comes from:

- Keep one diagram to roughly one paragraph's worth of information — Google's rule of thumb is no more than about five bullet items' worth.
- Simon Brown's own figure is that any diagram with twenty or more elements, "perhaps fewer", starts to get complicated quickly. It is deliberately hedged; do not harden it into a cap.
- What readability research actually supports is that **edge crossings**, not node count, predict how hard a diagram is to read. Reroute before you shrink.
- When it gets crowded, split into several simpler diagrams, each focused on one area, use case, or bounded context, and each held at the same level of abstraction. Splitting genuinely costs the big picture, so keep one deliberately coarse overview and push detail into the per-area diagrams.
- Do not justify a limit with Miller's 7±2. That was a recall experiment, a diagram is inspected rather than memorised, and Tufte's objection is that the paper neither states nor implies any rule about how much to show.

## Rendering surface

- **Unknown or plain-text renderer, including a terminal**: box-drawing ASCII, inline. This always renders, so it is the default.
- **Confirmed Mermaid renderer**: worth switching once ASCII alignment starts fighting back. Mind the syntax traps in the reference, and prefer a `flowchart` with `subgraph` boundaries over Mermaid's own `C4` type, which its docs mark experimental and which lacks legends, line styles, and layout control.
- **A published deliverable**: follow the host's diagramming guidance for that surface, such as `artifact-diagramming` for artifacts, instead of the ASCII conventions here.
- Never promise a diagram on a surface you have not confirmed renders it. A broken fence is worse than an ASCII box.

Templates for each diagram type, the caption-first workflow, and the Mermaid traps: [diagram patterns](references/diagram-patterns.md).

## Prose budget

- Lead every paragraph with its point. Readers focus on opening sentences and skip what follows.
- Three to five sentences per paragraph reads well; past about seven, readers avoid the paragraph outright. A run of one-sentence paragraphs signals missing structure, not tight writing.
- A list needs more than one item, parallel phrasing, and a complete sentence introducing it. Reach for a table only when each row carries three or more related fields; a two-column table is a list.
- Refer to a figure by its name or number, not as "the diagram above". Position moves; names do not.
- Cut prose that walks the reader through what the picture already shows. Spend that space on why the boundary sits where it does, where it is fragile, and what breaks first under change — separating structure from rationale is exactly what arc42 and the ADR tradition formalise.
- Cite `file:line` for every claim about code.

## Anti-patterns

| Symptom                                                     | What it actually is                |
| ----------------------------------------------------------- | ---------------------------------- |
| Boxes and lines with no labels                              | "related somehow", drawn           |
| One diagram holding classes, containers, and business areas | Mixed abstraction                  |
| Prose narrating the diagram from top to bottom              | The flood, re-shaped               |
| A chapter outline on a four-paragraph answer                | Scaffolding for its own sake       |
| An edge you could not find in the code                      | Fabrication                        |
| A third regeneration of the same diagram                    | Ask what is actually wrong instead |

## Stop condition

Stop when the reader can point at the diagram and say where a change would go. Everything past that is the flood this skill exists to prevent.

The sourced basis for these rules, including the two places the sources disagree and what this skill deliberately does not claim, is in [evidence](references/evidence.md).
