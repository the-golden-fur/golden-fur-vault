# Configurable pricing rules

Branch: `31-configurable-pricing-rules`

Live follow-up feedback on `28-fix-pricing-matrix`'s optional weight/coat
matrix, given in the same conversation before that change was ever
committed - a distinct request, so it gets its own numbered folder per this
repo's one-request-per-folder convention.

## Why

Looking at `/staff/admin/maintenance/pricing-configuration` after #28
shipped its optional-matrix toggle, three follow-up asks came back together:

1. "I don't like that long coat is just a flat price add on, shouldn't it
   be a multiplier as well" - Long coat had exactly one adjustment type
   (flat add-on), while every size had exactly one different type
   (multiplier). Neither was configurable.
2. "Actually separate each size and coat, make it so that I can
   individually set for each size/coat if I want it to be a multiplier
   type, flat price add on, or something like percentage. I would be able
   to config small size to be either flat, multiplier, percentage, etc."
3. "Also make them into their full names, not just abbrev (size S > Small
   size)."

Before this change, `deriveGroomingMatrix` (server and client copies) had
exactly one formula: `sizePrice = base_price * size_multiplier`, then
`coatType === 'LC' ? sizePrice + long_coat_addon : sizePrice`. Multiplier
and flat add-on were hardcoded to size and coat respectively - there was no
way to make Small a flat add-on, or Long coat a multiplier, or either one a
percentage.

## What changed

### DB

`supabase/migrations/20260807108_m13_configurable_pricing_rules.sql`:

- `create type public.pricing_rule_type as enum ('multiplier', 'flat', 'percentage')`.
- `pricing_configuration`'s five numeric columns are **renamed**, not
  replaced, so every already-configured value carries forward unchanged:
  `size_s_multiplier` → `size_s_rule_value` (same for `_m_`/`_l_`/`_xl_`),
  `long_coat_addon` → `coat_long_rule_value`.
- Each renamed value column gets a matching `..._rule_type
pricing_rule_type not null` column - `'multiplier'` default for the four
  sizes (preserving old behavior exactly), `'flat'` default for
  `coat_long_rule_type` (ditto).
- The old `> 0`-only CHECK constraints (multiplier-only semantics) are
  replaced with `>= 0` (a flat/percentage rule can legitimately be zero); a
  multiplier of exactly zero is instead rejected at the application layer,
  where the paired `rule_type` is actually known (see Server below).

### Server

- `maintenance.types.ts` - new `PricingRuleType = 'multiplier' | 'flat' |
'percentage'`; `PricingConfiguration` interface redesigned to five
  `{type, value}` pairs (`size_s_rule_type`/`size_s_rule_value`, ...,
  `coat_long_rule_type`/`coat_long_rule_value`).
- `deriveGroomingMatrix.ts` (server and client, kept in sync manually - no
  shared module between the two builds) - rewritten around a generic
  `applyRule(runningPrice, basePrice, type, value)`:
  - `multiplier`: `runningPrice * value` (scales the running total).
  - `flat`: `runningPrice + value` (adds a fixed peso amount).
  - `percentage`: `runningPrice + (basePrice * value) / 100` - **always**
    against the service's own `base_price`, never the running
    (already-size-adjusted) total, so the coat rule's math never depends on
    which type the size rule happened to use.

  Each size rule is applied to `base_price` first; the coat rule (if Long
  Coat) is then applied to that size-adjusted result. With the seeded
  defaults (`multiplier` for every size, `flat` for coat) this reproduces
  the exact prior formula.

- `maintenance.validator.ts` - `updatePricingConfigurationValidator`
  redesigned to the five `{type, value}` pairs (all optional, PATCH
  semantics unchanged); a new `rejectZeroMultiplier` superRefine rejects a
  `_rule_value` of exactly 0 only when its paired `_rule_type` is
  `'multiplier'` **in the same request** - a flat/percentage rule may
  legitimately be 0, and a single-field PATCH that doesn't touch the type
  is trusted as-is.

### Client

- `maintenance.types.ts` - mirrors the server type redesign; new
  `PRICING_RULE_TYPES` array for building the type `<select>`.
- `PricingConfigurationPage.tsx` - full rewrite. A new `RuleField`
  component (type `<select>` + value `<input>`) renders once per size and
  once for Long coat, each independently configurable. Labels use full
  names throughout ("Small size", "Medium size", "Large size", "Extra
  Large size", "Long coat") instead of "Size S"/"Size M"/etc - purely a
  copy change, the underlying `size_s_*`/etc. keys are unchanged.
- `PricingMatrixPreview.tsx` - unchanged (it already read `WEIGHT_LABELS`
  full names like "Small (S)"; the derived-cell math flows through the
  rewritten `deriveGroomingMatrix` automatically).

## Verification

### 1. Migration

- **With Supabase CLI access**: `supabase db reset` (fresh local db) or
  `supabase db push` (linked remote project).
- **Without CLI/push access**: Supabase Dashboard → **SQL Editor** → paste
  `configurable-pricing-rules.sql` in this folder → **Run**. Confirm with:

  ```sql
  select size_s_rule_type, size_s_rule_value,
         coat_long_rule_type, coat_long_rule_value
  from public.pricing_configuration;
  ```

  Expect `size_s_rule_type = 'multiplier'`, `size_s_rule_value = 1.0000`
  (or whatever was previously configured as `size_s_multiplier`),
  `coat_long_rule_type = 'flat'`, `coat_long_rule_value` carrying forward
  whatever `long_coat_addon` held.

### 2. Every size and Long coat are independently configurable

1. As Admin/Superadmin, open `/staff/admin/maintenance/pricing-configuration`.
2. Confirm five rule sections, each with a type dropdown (Multiplier / Flat
   add-on (PHP) / Percentage add-on (% of base price)) and a value input:
   **Small size, Medium size, Large size, Extra Large size, Long coat** -
   full names, not "Size S"/etc.
3. Set Small size to Flat add-on / ₱50, Large size to Percentage add-on /
   25, Long coat to Multiplier / 1.5. Save.
4. Scroll to the Preview section, enter a sample base price (e.g. 300).
   Confirm: Small/Short Coat = 350 (300 + 50 flat); Large/Short Coat = 375
   (300 + 25% of 300); Small/Long Coat = 525 (350 size-adjusted \* 1.5
   multiplier).

### 3. A multiplier of 0 is rejected; a flat/percentage 0 is accepted

1. Set any size's type to Multiplier and its value to 0 - saving should be
   rejected client-side (and server-side, if attempted directly via the
   API) with a message that a multiplier can't be zero.
2. Set that same size's type to Flat add-on and its value to 0 - this
   should save successfully (Short Coat and Long Coat both end up equal to
   base_price for that size, same as before this change existed at all).

### 4. Existing Grooming services still price correctly through the rewritten formula

1. With the pricing rules left at their seeded defaults (every size
   Multiplier, Long coat Flat), open a matrix-enabled Grooming service
   (e.g. Bath, from `28-fix-pricing-matrix`) and confirm its preview matrix
   is unchanged from before this change - the default rule types reproduce
   the prior hardcoded formula exactly.
2. Book that service for two differently-sized/coated Dogs and confirm the
   charged prices still match the preview, as in #28's own verification.

### 5. API-level checks (Postman)

See `configurable-pricing-rules.postman_collection.json` in this folder.

1. Import the collection, fill in `admin_identifier`/`admin_password`.
2. Run requests in order. All Test Results should be green - covers
   `GET`/`PATCH /maintenance/pricing-configuration` with the new
   `{type, value}` shape, a zero-multiplier rejection, and a zero-flat
   acceptance.

## Test suites

- `server`: `npm run test` (from `server/`) - 751/751 passing.
  `deriveGroomingMatrix.spec.ts` rewritten for the new fixture shape, plus
  a new case mixing a percentage size rule with a multiplier coat rule;
  `maintenance.validator.spec.ts`'s `updatePricingConfigurationValidator`
  suite rewritten for the `{type, value}` pairs and the
  zero-multiplier-only-when-paired refinement; `services.service.spec.ts`
  and `booking.service.spec.ts` fixtures updated to the renamed fields.
  `npx tsc -b` clean.
- `client`: `npm run test` - 540/540 passing.
  `deriveGroomingMatrix.spec.ts`, `PricingMatrixPreview.spec.ts`, and
  `PricingConfigurationPage.spec.ts` all rewritten for the new fixture
  shape and full-name field labels (`AdminServicesPage.spec.ts`'s
  `PRICING_CONFIGURATION` fixture updated too, since its embedded matrix
  preview shares the same derivation). `npx tsc -b` clean.
