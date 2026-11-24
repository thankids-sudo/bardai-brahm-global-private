# Claude project memory and implementation brief

Updated: 25 November 2026, India time.

## Start here

You are taking over development of a real native Android application for **બરડાઈ બ્રહ્મ ગ્લોબલ ફાઉન્ડેશન — Bardai Brahm Global Foundation**. Act as product developer, Android engineer, backend engineer and practical technical lead. Read this entire file, inspect the repository and its instructions, then implement the first milestone. Do not restart requirements gathering for decisions already confirmed below. Ask only for actual blockers. This file describes agreed requirements and proposed implementation; it is not evidence that features already exist.

## Owner and confirmed decisions

- Project owner: Dhaval Thanki. GitHub account: `thankids-sudo`.
- Repository: https://github.com/thankids-sudo/bardai-brahm-global-private
- Clone URL: https://github.com/thankids-sudo/bardai-brahm-global-private.git
- Foundation is being established; do not claim legal registration is complete.
- Start worldwide, with Gujarati and English from the first release.
- Any Bardai person can apply. Relevant chapter secretary approves membership.
- Global Administrator email designated by owner: `Thankids@gmail.com`. Email verification and server-side role assignment are mandatory before activation.
- Verified members may search across all worldwide chapters.
- Phone/email visibility requires individual permission.
- No existing membership spreadsheets or family registers: start with fresh registrations.
- ₹20,000/year is the budget for hosting and online services only. Development labour is excluded. No paid service purchase has been authorised.
- Survey includes both demographic/population and domicile/residence information, plus socioeconomic data.
- Basic genealogy means family relationships, not genetic testing or DNA data storage.

## Actual repository status at handover

The repository was created by the owner. Latest observed state was empty. GitHub metadata reported visibility `public`, despite the name ending in `private`; signed-out browser access also displayed the empty repository. Recheck before work and tell the owner if still public. Never assume its name establishes privacy.

An attempt to create README.md through the connected integration failed with HTTP 403, `Resource not accessible by integration`. The account metadata showed push/admin permission, but that did not establish integration write access. No files were uploaded, no branches or workflows were created, and no APK was built. The browser was signed out. Claude must establish its own repository access; never claim the earlier upload succeeded. If access is blocked, prepare the complete project locally and give exact instructions to grant the integration access or push it, without requesting tokens in chat.

## Logo and visual identity

Owner supplied `1001606100.png`. Attach this image alongside this memory file in Claude. The old ChatGPT-only local path was `/workspace/scratch/da867a665f6a/upload/01-1001606100.png`; it is not a portable download link and Claude should not expect that path to exist.

The emblem contains a navy/gold circular border, green banyan tree, seated white-clad figure, foundation name, and the wording `SANT TRIKAMACHARY MAHARAJ`. Preserve supplied artwork and lettering. Use navy, gold, green and warm white for the UI. Keep a master image under `branding/`, with optimised Android resources generated from it. Do not redesign or substitute a generic logo. Full emblem belongs on welcome/login/About screens; use sufficient safe padding for Android adaptive icon masks. If small-size lettering is illegible, propose an alternate compact icon for owner review while retaining the full emblem. Do not block implementation on branding refinements.

## Product modules

### 1. Identity and membership

Email registration → email verification → basic profile → residence chapter selection → secretary review → approved membership.

Email control and community membership are distinct checks. Pending accounts can manage their application and their own permitted information, but cannot search the verified directory. Membership statuses: pending, correction requested, approved, suspended. Keep rejection/appeal and duplicate-account handling explicit. Assign immutable member IDs and separate household IDs. Do not use email as a person's permanent identity key.

Adults without an account, deceased ancestors and children can have appropriate person records without separate logins. Assisted registration must record who entered information and the consent basis; never impersonate a relative. If no local chapter exists, route applications to a temporary global membership secretary. That role has not been appointed; do not invent a name or silently assign it to another user.

### 2. Person records and family tree

Capture name, surname, optional former surname, optional photo, birth date/year, living/deceased status, birthplace, present residence and ancestral village. Each related person's village belongs to that person's record, not one shared village field.

Relationships: father, mother, paternal grandfather/grandmother, maternal grandfather/grandmother, spouse, father-in-law, mother-in-law, children and siblings. Derive sibling/in-law views from links where possible. Support unknown ancestors, adoption, step/guardian links, remarriage and half-siblings respectfully. No binary assumption that excludes valid family structures.

Separate account, person, household, residence and relationship entities. Support multiple residences over time and time-bounded household membership. Never merge people automatically because name, surname or village matches. Suggest duplicates for review. Relationships entered for another living adult are unconfirmed until accepted or appropriately reviewed. Preserve provenance, corrections, disputes and edit history. Invitation/claim flows must prevent takeover of an existing person record.

Family tree views should expand both parental branches; later add relationship finder, family history/photos and permission-aware PDF export. Living-person relationship details stay restricted by default. Directory visibility does not grant access to a whole family tree.

### 3. Survey

Separate individual and household questionnaires to avoid duplicate household income counting.

Individual: age/year of birth, optional demographic fields justified by purpose, education level/subject, current study, vocational skills, employment status, occupation/industry, optional business listing, ancestral village, present country/state/city, optional migration year, mentoring/volunteer interests.

Household: household size, earning members, optional annual income band, currency, reporting year, owned/rented/other housing, education/career/senior/emergency support needs. Offer `Prefer not to disclose`. Do not require exact income, bank details, Aadhaar or DNA files. Support needs must not become public directory fields.

Use questionnaire versions and timestamps. Keep incomplete, self-reported and verified statuses distinct. Country-specific income bands require an explicit method; never compare raw cross-country currencies as equal living standards. Surveys should support saving progress with appropriate device protection; defer sensitive offline storage until secure handling is implemented.

### 4. Chapters and roles

Hierarchy: global → country → state/province → district/region → city/local. Permit omitted levels and country-specific terminology.

Roles: global administrator, country administrator, state/province administrator, local chapter administrator, chapter secretary, assigned survey volunteer, member. Secretary is a distinct permission even if held by a chapter admin. One primary residence chapter; optional ancestral/former residence affiliations without duplicate member counts.

Permissions enforced by backend, scoped to chapters and specific actions. A chapter administrator must not automatically see private income or all family data. Separate administrative authority from sensitive-data access. Record appointments, revocations, approval actions and audited exports. Parent chapter management and report scope need explicit policies, not unrestricted database reads.

### 5. Directory

Verified members search worldwide by approved name/surname, profession, chapter, ancestral village and broad location. Show only consented fields. Do not expose exact address, private contact details, household economy, children or unconfirmed relatives. Enforce the same rules in search, APIs, exports and caches. Rate-limit enumeration and bulk downloads.

### 6. Events and communication

Worldwide timezone-aware calendar, chapter/country filters, organiser, venue/online link, RSVP, reminders, capacity and attendance. Authorised chapter admins can upload compressed event pictures, captions and reports with moderation/removal procedures. Avoid publishing private participant information in public albums.

First release: official chapter announcements and external meeting links. Meeting host controls and participant permissions belong to the meeting provider initially. Built-in video is deferred. Moderated chapter/interest-group chat follows the pilot, with reporting, blocking, rate limits, moderator permissions and retention rules. Do not show placeholder chat or video as working functionality.

### 7. Statistics dashboard

Counts for registered people, approved members, surveyed households and any population estimates must be separate. Show country/state/city/village distribution, age groups, education, profession, employment/job-seeking, local income bands, support needs, events and survey completion. Include update time, denominator, missing responses and duplicate-resolution status. Do not label voluntary responses a complete census or infer unobserved population without a documented method.

Use aggregated permission-aware endpoints. Suppress small groups and combinations that could identify families, including through filters/differencing. Define suppression rules before enabling sensitive breakdowns. Members may see safe aggregates; authorised planning users may see additional aggregates, not unrestricted row-level survey data.

## Privacy, security and governance

Design consent separately for membership, surveys, family sharing, directory listing, photos and notifications. Provide correction, deletion, optional-sharing withdrawal, grievance contact and a clear retention policy. Living adults should control their own visibility. Handle children's data with guardian consent and restricted visibility; first pilot should use adult accounts rather than child logins.

No real member data, production database dumps, signing keys or privileged backend keys in git. Keep development/staging/production separate, use synthetic test fixtures, encrypt transport, implement server-side authorisation and restrict media URLs. Public mobile configuration is not a substitute for security policies. Store privileged keys only on the backend. Audit logs must avoid sensitive payload leakage.

Bootstrap the global admin using a verified auth identity and a controlled one-time backend operation. Never grant global administration in client code just because someone typed the designated email. Require stronger authentication for administrators and offer session revocation. Account deletion must account for related family-tree records without publishing or orphaning other people's private data; document anonymisation and any justified retention.

Before launch, check then-current Google Play Data Safety/account deletion/user-content rules, Indian data-protection commencement and applicable overseas requirements. Historical research found India's DPDP framework had phased commencement; do not treat every provision as already effective. Do not claim global compliance from one consent checkbox. Obtain appropriate review for the actual deployment scope.

## Technical direction: agreed versus proposed

Agreed: native Android, Gujarati/English, GitHub-based development/builds, web administration portal, shared backend, annual service budget ceiling.

Proposed: Kotlin + Jetpack Compose, version-controlled compatible Gradle/Android plugin/Kotlin dependencies, relational backend suitable for genealogy and households, object storage for photos. Backend vendor and hosting region have NOT been selected. Evaluate current official prices/quotas, backups, email delivery, privacy requirements and expected usage. Do not promise unlimited worldwide capacity for ₹20,000. Do not purchase services without owner authorisation.

Indicative budget allocations, NOT supplier quotations: backend/hosting ₹8,000, media/backups ₹3,000, domain/email ₹3,000, contingency/monitoring ₹6,000. Reallocate based on verified costs. Include CI/storage costs, exchange rates/taxes and usage limits in the final projection. Domain name and store account are not yet selected/provisioned.

Use a maintainable architecture with UI, domain/repository interfaces and data layer. Keep preview fixtures separate from production. Backend schema should include accounts/profiles, persons, relationships, households/memberships, residences, chapters, scoped roles, member applications, consents, survey versions/responses, events, RSVPs, media, moderation and audit events. Choose a simpler relational implementation first; a graph database is not required merely because genealogy is a graph.

## Suggested repository layout

```text
android/                 Native app, Gradle wrapper and resources
admin-web/               Web administration portal, introduced when implemented
backend/                 Migrations, policies, server functions and tests
branding/                Supplied master logo
docs/                    Requirements, permissions, questionnaire, deployment
.github/workflows/       Android checks and build workflows
CLAUDE.md                Concise working instructions referencing this brief
README.md                Honest current status and setup instructions
```

Adapt to existing repository conventions if it is no longer empty. Read AGENTS.md/CLAUDE.md and inspect existing changes before editing. Do not overwrite unrelated work.

## GitHub build and delivery process

1. Establish actual read/write access; recheck visibility and default branch. Use a feature branch and reviewable commits where possible.
2. Commit complete Android project including Gradle wrapper, exact compatible dependency versions, bilingual string resources and source logo derivatives.
3. On pull request/push run compile, Android lint and meaningful tests. Use supported actions, minimal token permissions and safe handling of untrusted pull requests. Keep secrets unavailable to untrusted contributions.
4. Build a debug APK automatically and upload it as a named artifact, with retention set to control storage. Use a manual workflow trigger too.
5. A clean runner must build successfully. Bootstrap wrapper tooling if necessary before claiming CI is ready. Do not ship a fake wrapper or a workflow referring to missing files.
6. Debug builds are for testing. Explain when debug signing may require reinstalling; do not distribute unstable signing identities as production updates.
7. Add a separate protected release workflow only once signing is configured. Produce signed APK for direct installation and AAB for Play. Preserve upload/signing keys securely outside source control and explain backup/recovery.
8. Report exact commit, run URL, status, artifact and checks actually executed. Never call a written YAML file a successful build. GitHub hosts source/build artifacts; it is not the member database backend.

## Milestones and acceptance checks

### M1 — Bilingual branded Android preview (first task)

Installable APK with supplied logo, Gujarati/English switch, readable typography, navigation and previews of Home, My Family, Chapters, Events, Survey and Profile. Clearly label preview/demo state; show no invented live membership totals, operational login or admin claims. No collection of real private data. Include empty/error/loading states where relevant. Android system splash limitations may require placing the full emblem on an in-app welcome screen.

Pass: clean GitHub build succeeds; artifact APK installs/launches on a supported device or emulator; language switch works and persists; logo is not cropped; no secrets; no false backend claims. If device testing is unavailable, report that limitation explicitly.

### M2 — Identity and membership vertical slice

Select backend after comparison; implement email verification, applications, chapter routing, controlled admin bootstrap and secretary approval. Pass: unverified/pending/suspended accounts cannot query the directory; secretary cannot approve another chapter's members; users cannot self-promote; audit trail records approvals.

### M3 — Person, household and family links

Implement editable profiles, households, both parental branches and relationship confirmations. Pass: no duplicate counting; unconfirmed links marked; private relatives do not leak; merge conflicts require review; invalid relationship cycles are blocked appropriately.

### M4 — Survey and safe dashboard

Versioned bilingual questionnaires, optional answers, household income once per household, aggregate endpoints and suppression. Pass: household totals reconcile; missing answers do not become zeros; currency/reporting year retained; filters do not reveal small groups.

### M5 — Worldwide directory and chapter events

Permission-aware search, announcements, RSVP, calendar and compressed photos. Pass: contact choices enforced server-side, timezone conversion correct, upload permissions and removal work, chapter roles scoped correctly.

### M6 — Pilot and later communication

Pilot with roughly 50–100 consenting households across two or three chapters, with worldwide registration available. Assess usability, cost, duplicates, secretary workload and consent before expansion. Add moderated chat after pilot; built-in video, payments, advanced ancestry exports and welfare workflows remain later options, not first-release commitments.

## Working expectations for Claude

- Proceed with authorised reversible implementation choices; do not repeatedly ask for already-confirmed requirements.
- State important assumptions and keep proposed choices distinct from owner decisions.
- Produce complete working files rather than isolated snippets; keep change scope reviewable.
- Test high-risk authorisation and privacy behaviour with meaningful negative tests. Do not write trivial tests solely to inflate coverage.
- Use official current technical documentation when resolving toolchain/API compatibility; do not invent package versions or price quotations.
- Keep UI language simple and bilingual; implementation details belong in developer docs.
- If blocked by repo access or credentials, finish all independent local work and describe the precise blocker. Do not claim a deployment, email send, membership approval or APK build happened without evidence.
- Keep `docs/PROJECT_STATUS.md` updated with implemented, tested, partial, deferred and blocked items, plus the next concrete step.

## First instruction to execute

Read this memory and inspect the repository. Confirm access and current status, then implement M1 end to end with the supplied logo and an automated debug APK workflow. Do not enable production registration or accept real survey data until M2 security is implemented. At completion, return commit/PR and build links, APK access instructions, checks performed and remaining blockers. Then propose exactly one next implementation slice.

## Research references from planning (recheck for implementation)

- Android command-line builds: https://developer.android.com/build/building-cmdline
- GitHub Actions secrets: https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets
- GitHub workflow artifacts: https://docs.github.com/en/actions/concepts/workflows-and-actions/workflow-artifacts
- Google Play account deletion: https://support.google.com/googleplay/android-developer/answer/13327111
- Indian DPDP Rules official index: https://www.meity.gov.in/documents/act-and-policies/digital-personal-data-protection-rules-2025-gDOxUjMtQWa
- FamilySearch living-person privacy design reference: https://www.familysearch.org/en/help/helpcenter/article/what-is-a-private-space-in-family-tree
- Existing Bardai community organisation, possible voluntary collaboration reference only: https://www.bardaionline.com/

These references are context, not proof of registration, affiliation, partnership or compliance.
