-- Enum values used by the survey/statistics migration. Kept in their own migration so they are
-- committed before use (PostgreSQL forbids using a new enum value in the transaction that adds it).
alter type app.consent_purpose add value if not exists 'survey';
alter type app.role_kind add value if not exists 'planning_analyst';
