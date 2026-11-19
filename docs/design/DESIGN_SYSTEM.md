# NetoSensei assistant design system

Reuse CardView for grouped evidence and native NavigationStack, List/ScrollView,
Button, ProgressView and Label. Typography uses .title2, .headline, .body,
.subheadline and .caption; no fixed-size body text. System .primary and .secondary
foregrounds adapt to appearance. Color.accentColor means action; .secondary means
unknown, unmeasured or unsupported; orange is a caution with an explanation.

Spacing: 16 points between cards, 12 between rows, at least 44-point tap targets.
Primary buttons use borderedProminent, secondary buttons bordered; running work
shows a ProgressView and disables conflicting actions. No decorative motion or
translucent content surfaces. Labels wrap at accessibility sizes.

Reusable primitives: AssistantEvidenceRow for label/value/explanation and
AssistantCapabilityRow for capability/availability/reason. State is expressed
with text, not only color. Device recognition is per scan because an IP or
self-advertised name is not an authenticated identity. No credentials in chat.
