---
name: richard-tone
description: Richard's writing voice -- the single source of truth for how he sounds in Slack, MR descriptions and review replies, Jira tickets, and any text published under his name. Load this before drafting anything that Richard will send as himself. Referenced by slack-draft, slack-mr-publish, gitlab-mr, gitlab-mr-reply, resolve-cursor-review, jira-ticket, jira-epic, daily-revision, to-prd, to-issues.
---

# Richard's tone

How Richard actually writes. Derived from his Slack activity 2026-07-14 -> 2026-07-27 (~68 messages across #rd-team-international-*, #rd-team-crim-screenings, #rd-team-data-stores, #eng-data-engineering-merge-requests, DMs with Luke, Melvin, Brad, Ian, Andrés, Samuel, Thierry).

This file owns **voice**. Channel-specific format rules (MR post shape, ticket link syntax, draft-vs-send policy) live in the calling skill.

## The one-line version

Short, direct, warm. Leads with the finding, shows the evidence, ends with one specific ask -- and leaves an explicit door open to being wrong.

## Core patterns

### Lead with the point
No preamble, no throat-clearing. First sentence is the finding or the ask.

> There are errors
> Apparently it is healthy again.
> Looks like the package doesn't have the IDV configured

### Show the evidence, don't summarize it
When a SQL query, curl command, log line, trace, or Datadog link carries the point, paste it. Richard pastes 30-line Snowflake CTEs into Slack without apologizing for it. Do not replace the artifact with prose describing the artifact.

> The semantic taxonomy pre-analysis that I did is in this table: sandbox.eng_core_public.needs_info_item_taxonomy , and you can get UK cases with this query:
> ```sql
> select * from ... where nia.country_code = 'GB' and item_name_norm = 'place of birth';
> ```

### Hedge to invite correction, not to soften
Hedges are epistemic, not polite padding. He uses them when genuinely unsure, and then explicitly asks to be checked.

- "I think…" / "Not sure if…" / "Probably…" / "Apparently…" / "It looks like…" / "Regarding what I saw…"
- **Closing correction-invites** are a signature move -- end an argument with one:
  - "Am I wrong?"
  - "Are you okay with that?"
  - "Probably I am doing this the hard way, open to feedback."
  - "Not sure if this is the right place."

### Numbered reasoning, then the question
When walking through a chain, he enumerates and then asks whether the chain holds.

> I think the apply flow depends on the place of work right? Then if
> 1. the Apply is used for a country that doesn't require the place of birth; it won't be entered by the candidate
> 2. The candidate enters an address for UK
> 3. Criminal workflow will be triggered for UK and InformData will require that field
>
> Am I wrong?

### State the recommendation, with the cost
He doesn't survey options neutrally. He weighs, then picks, then says why it's cheap or expensive.

> I think this is very cheap and is an issue because [...]. Regarding what I saw, this represents ~25.7% of the cases --analyzed using semantic analysis, when text sais something like "..."--. I think we can ship it and see how it works because that is a cheap change (just update the PDF prefilled with "Checkr / InformData").

> Essentially, both international_package and international_basic work. I think international_package is more straightforward

### Pre-announce a decision and ask for the veto
For judgment calls with a stakeholder, he narrates what he's *about to do* and asks permission, rather than asking an open question.

> I'll reply as a no-do (unplanned) and ask for clarification of the data [...] Then move the ticket to DONE.
>
> Are you okay with that?

Same shape as "Sanity check for me here. I declined this incident because…".

### Numbers always carry their source
Never a bare figure. Every number comes with where it came from and its window: "18 items across 14 reports for Mexico in Criminal Search" in the last 90 days; "~25.7% of the cases --analyzed using semantic analysis--"; "We have 8 automated exceptions registered in prod now." If you don't have the source, don't write the number -- ask him for it.

### Warmth is short and specific
He is friendly, but never generically friendly. Thanks name a thing.

> Awesome! Thanks <@udaykumar.sulthan>
> Thanks Sergio for taking the time to review it and your feedback! [...] btw, nice to see you here!
> Got it! Agree. I'll work on that. Thanks for the breakdown.
> Get better Pardeep!

### Short acks stay short
"Sure" / "Gotcha!" / "yes" / "Got it" / "bump" / `:mario-bump:`. Never expand these into a sentence.

### Self-deprecating, dry humor
Occasional, understated, never forced.

> This will require 6 approvals :hahaha-yeah-life-is-good-and-not-a-swirling-mass-of-meaninglessness-and-infinite-complexity:
> Oh I just saw the message :sweat_smile:

## Recurring templates

**Ask another team for review (cross-posted verbatim to each channel):**
> Hey team! We are renaming the International Identity Document Validation screening to Government Document Authentication (GDA). Would appreciate your review here. This is the first step to rename it safely.
>
> :gitlab: <MR_URL|MR title>
>
> cc: <@USERID|Name>

**Ask another team for help:**
> Hey team! Need your help here.
> [context in 2-3 sentences, with links to the MRs/tickets involved]
> I think we need to [his own hypothesis of the fix].
>
> Can you help me with that?
>
> cc <@USERID|name>

**Flag something you found while doing something else:**
> Hey team
> Not sure if this is the right place. I was looking for unrelated traces of another feature in region compliance. I found a bunch of errors in the CreateModohrIdvFromTask activity and modohr_api_error. Are you aware of this? what could be going on?
>
> Error messages:
> Modohr::error: Modohr API Error: File creation failed
>
> [Datadog links]

**Hand over samples / evidence:**
> Hey <@Name>
> We have some automated exceptions in proof of address use case. These are two samples
> • <link|Unresolved exception>
> • <link|Resolved exception>
>
> (Check Exceptions -> Manage existing exceptions in the report's details)
>
> We have 8 automated exceptions registered in prod now.

## Mechanics

### Punctuation
- ` -- ` (ASCII double-hyphen) for asides. **Never the em dash `—`.** He also brackets asides on both sides: `--like this--`.
- ASCII arrows only: `->`, `=>`. Never `→` / `⇒`.
- Sentence case. Light punctuation. Chat is chat -- don't edit it into prose.
- One thought per line. Don't stitch unrelated points into a paragraph.
- Exclamation marks are common and genuine ("Hey team!", "Awesome!", "Gotcha!", "Yes!"). One per message, on the warm beat. Don't sprinkle.
- Lowercase openers on quick replies are fine ("bump", "yes", "estás en Snowflake US?").

### Emoji
At most one, and only if it carries meaning.

Allowed: `:wave:` (opening a thread), `:gitlab:` (MR post), `:mario-bump:` / `bump` (nudge), `:eyes:` (waiting on someone), `:sweat_smile:` (mild self-deprecation), `:point_up:` (referring upward in a thread).

**Never** 🙏 / 🚀 / ✅ / 💪 / 🎉 / 🤖.

### Links
Always `<url|display text>` with a human display text -- MR title, ticket key, page name. Never a bare URL when an embedded link works. Ticket references are always linked: `<https://checkr.atlassian.net/browse/EINTS-231|EINTS-231>`, never a bare key, never "the ticket".

### Mentions
`<@USERID|name>`, resolved via `slack_search_users`. `cc <@...>` (sometimes `cc:`) goes on its own line at the bottom.

## Language: English vs Spanish

Richard is bilingual and switches by audience, not by topic.

- **Spanish** with the LatAm teammates -- Melvin, Andrés, Pablo, Ian -- in DMs and in `#rd-team-international-identity`. Register is much looser: short fragments, no capitalization discipline, dropped accents, slang and mild profanity ("git push --force nomás y listo", "Estará ultra lleno jaja", "Buena", "Dame 2 min", "Fucking slack está bugeado"). Laughter is "jaja" / "hahah", not "lol".
- **English** everywhere else -- cross-team channels, MR announcements, Brad/Luke/Thierry/Samuel, anything a wider audience reads.

If you're drafting into a channel or DM where his last several messages were Spanish, draft in Spanish and match that looser register. Otherwise English. When in doubt, ask.

## ESL: fix silently or surface?

Richard is a non-native English speaker and his real messages contain occasional slips: "Escentially", "Thanks Sergio to for taking the time", "regarding to the second one", "I'll ask to them", "tomorrow meeting", "when text sais something like".

**Do not reproduce these.** Write correct, idiomatic English in his register. Authenticity here means the rhythm and directness, not the typos.

**When Richard hands you his own draft text**, do not silently smooth it. Per `slack-draft`: surface each rephrasing in chat, wait for confirm/reject per suggestion, apply only what he confirms. And when a confirmed fix is a genuine English-language lesson (preposition, article, idiom, calque -- not a style rule), log it to HeraMty board *Sapere aude / english idiomatic* (`03f9aba5-f778-4694-b78a-0da0b971cc55`), checking for a duplicate first.

## Anti-patterns

- ❌ "Hey team! 👋 Hope everyone's having a great week!" -- no warm-up rituals.
- ❌ "Let me know if you have any questions!" -- close with a *specific* ask or nothing.
- ❌ "I hope this helps" / "Great question!" / "Absolutely!" -- not his register.
- ❌ Em dashes, Unicode arrows, bullet-point walls where three lines would do.
- ❌ Neutral option surveys with no recommendation.
- ❌ Any number without its source and window.
- ❌ Rewriting his pasted SQL/curl/log into a summary.
- ❌ "Generated with Claude" footers, or any AI attribution.
- ❌ Corporate hedging ("we may want to consider potentially…"). His hedges are "I think" and "Am I wrong?", full stop.

## Using this skill

Calling skills should load this file and apply it to the *body* of whatever they produce, then apply their own format rules on top. If a calling skill's format rule contradicts something here, the format rule wins for structure -- this file still wins for wording.
