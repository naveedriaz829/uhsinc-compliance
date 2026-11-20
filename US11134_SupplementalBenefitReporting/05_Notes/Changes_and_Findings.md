# User Story 11134 — Findings and Change Log

**Story:** 8032647 Compliance: 2026 Plan Reporting Supplemental Benefits  
**Working file:** `03_Development/SupplementalBenefits_2026.sql`  
**Original (unchanged):** `02_Original_SQL/Supplemental Benefit Utilization and Costs 2025-01-23.sql`  
**Review date:** 2026-11-21  
**Execution status:** No SQL executed against any database. No production connection. Status values below are code-review only.

---

## Current status

| Item | Status |
|---|---|
| CMS Part C Reporting Requirements (PDF, Section VIII) | Reviewed |
| BA Supplemental Benefit Excel workbook | Reviewed (header = `PBP Category_2025`) |
| 2026 PBP plan listing (`2026 PBP - Plan name listing 052825.xlsx`) | **Missing** — download from ADO into `01_Requirements/` |
| CY2026 Part C Technical Specifications | **Missing** — download from ADO into `01_Requirements/` |
| Development SQL safe object-name alignments | Changed (local only) |
| DEV validation query pack | Prepared (not executed) |
| End-to-end script test / data validation | **Not Tested** |

---

## What the existing SQL does (summary)

1. Sets control flags and `@REPORTING_YEAR` / `@START_DATE` / `@END_DATE`.
2. Loads QNXT benefit → SBSC mappings from PlanData into `CMSReporting.QNXT_Benefits_2026`.
3. When `@FULL_UPDATE = 'Y'`, deletes and rebuilds skeleton rows in `SupplementalBenefitUtilizationAndCosts_2026` for Contract/PBP × SBSC categories.
4. Optionally updates eligible-member counts from `MedicalEnrollAll`.
5. Applies PMPM/capitation costs from `SupplementalVendorRates`.
6. Applies usage-based utilization and costs from vendor/claim sources (LifeStation, ASH, Delta Dental, GA Foods, HCS, Incomm, NVA, QNXT claims).
7. Overlays interim vendor tables (Transportation, Meals, OTC, Activity Tracker).
8. Applies post-processing numeric “force-fit” adjustments, then optionally generates outbound files via BCP or returns a SELECT summary.

---

## Missing dependencies (do not invent rules)

1. **CY2026 Part C Technical Specifications** — Section VIII explicitly defers PBP Category Codes and upload/element technical rules to this document. Not in workspace.
2. **2026 PBP – Plan name listing 052825.xlsx** — Required to validate hardcoded `PrimaryMapping` plan columns and Contract/PBP inventory.
3. **Confirmation of 2026 vendor staging object names** — script still joins `Transportation_2025`, `Meals_2025`, `OTC_2025`, `Activity_Tracker_2025`.

---

## Task 3 — Classification of every `2025` occurrence in development SQL

| Line(s) | Occurrence | Class | Notes |
|---|---|---|---|
| 116, 144–160 | Commented `QNXT_Benefits_2025` alter/index history | **KEEP** | Historical / commented only |
| 530, 562 | Commented joins to `QNXT_Benefits_2025` | **KEEP** | Commented diagnostic code |
| 1184 | Commented update against `..._2025` | **KEEP** | Commented |
| 1481–1482 | Comments with `'2025-12-31'` / `'2025-01-01'` | **KEEP** | Active predicates already use `@END_DATE` / `@START_DATE` |
| 1495–1497 | Comment: Lyft / Transportation 2025 | **KEEP** (+ VERIFY note added) | Documents historical vendor feed |
| 1542 | `CMSReporting.Transportation_2025` | **VERIFY** | Need BA/Shreya confirmation of CY2026 table name/contents |
| 1565 | `CMSReporting.Meals_2025` | **VERIFY** | Same |
| 1585 | `CMSReporting.OTC_2025` | **VERIFY** | Same |
| 1605 | `CMSReporting.Activity_Tracker_2025` | **VERIFY** | Same |
| Was 56–202, 926, 1312, 1425, 1487 | Active `QNXT_Benefits_2025` / `...UtilizationAndCosts_2025` | **CHANGE** | Aligned to `_2026` — see Change log |

`@REPORTING_YEAR` was already `2026` in both original and development copies before this review (notes Change 001).

---

## Change log (code edits made)

### Change 002 — Align active QNXT benefits object name to `_2026`

| Field | Detail |
|---|---|
| Original reference | ~L55–202, L1312 (`QNXT_Benefits_2025` guard/count/messages/join while truncate/insert already used `_2026`) |
| Problem | Active path loaded `_2026` but guarded/counted/joined `_2025`, so empty-check and QNXT claim mapping could use the wrong year object |
| Change made | Active references updated to `CMSReporting.QNXT_Benefits_2026` |
| Reason | Internal consistency with existing truncate/insert targets; reporting year already 2026 |
| Supporting requirement | CY2026 reporting period (`@REPORTING_YEAR = 2026`); CMS Section VIII report period 1/1–12/31 |
| Validation required | DEV object-existence + row-count queries in `04_Validation/Validation_Queries.sql` |
| Status | **Changed** (Not Tested in DEV) |

### Change 003 — Align Delta Dental / Liberty Dental UPDATEs to `_2026` results table

| Field | Detail |
|---|---|
| Original reference | ~L926 (Delta Dental), ~L1425 / ~L1487 (Liberty Dental mandatory/optional) |
| Problem | `UPDATE supp` joined `SupplementalBenefitUtilizationAndCosts_2025` while the rest of the CY2026 pipeline initializes/updates `_2026` (NVA already correctly used `_2026`) |
| Change made | Active joins/targets changed to `SupplementalBenefitUtilizationAndCosts_2026` |
| Reason | Prevent writing CY2026 metrics into the prior-year results table |
| Supporting requirement | Section VIII CY reporting period; development script’s own `_2026` initialize block |
| Validation required | Confirm `_2026` table exists; after controlled DEV run, verify dental categories updated |
| Status | **Changed** (Not Tested in DEV) |

### Change 004 — Documentation comments only (vendor / date literals)

| Field | Detail |
|---|---|
| Original reference | Transportation block comment; dental date-literal comments |
| Change made | Clarified historical 2025 notes; did **not** rename vendor `_2025` tables |
| Status | **Changed** (comments only) |

### Not changed (intentionally)

- Vendor tables `Transportation_2025`, `Meals_2025`, `OTC_2025`, `Activity_Tracker_2025`
- Mean-as-median utilization logic (`MeanTransactionsPerMemberUsing` assigned to Element K)
- Post-processing force-fit UPDATEs (~L1609–1661)
- Hardcoded `PrimaryMapping` plan UNPIVOT lists
- `@FULL_UPDATE = 'Y'` default (dangerous in PROD; left as original behavior)
- Incomplete `OBJECT_ID('tempdb..CMSReporting.QNXT_Benefits_2026')` guard pattern

---

## Suspected issues not yet changed

| # | Location | Issue | Why not changed | Status |
|---|---|---|---|---|
| 1 | Many vendor UPDATE blocks (e.g. ~L737–850, 946, 1009, 1135, 1195, 1277) | Element K (“median utilizations”) is populated from `MeanTransactionsPerMemberUsing` (average/ceiling mean). OOP often uses `PERCENTILE_CONT` correctly. CMS Section VIII Element K requires **median**. | Fix requires agreed median formula per vendor unit; do not invent | **Pending Confirmation** |
| 2 | ~L1609–1661 | Force-fit adjustments invent/adjust values (e.g. net = median OOP + 2; median util = total − 10; set metrics to 1 when utilizers = 1) | Business intent unclear; possible prior-year remediation; needs BA/Shreya | **Pending Confirmation** |
| 3 | ~L57–59 | `OBJECT_ID('tempdb..CMSReporting.QNXT_Benefits_2026')` is an odd/incomplete guard for a permanent table | Risk of changing load behavior without author intent | **Pending Confirmation** |
| 4 | Vendor `_2025` staging tables | May be stale for CY2026 or may still be the approved object names | No evidence of `_2026` replacements in workspace | **Pending Confirmation** |
| 5 | `PrimaryMapping` UNPIVOT plan lists | One SELECT includes `H7680-802`, others omit it; list may not match 2026 PBP file | PBP listing missing | **Pending Confirmation** |
| 6 | BA workbook header `PBP Category_2025` + dental Old→New codes | Mappings may have changed for 2026; Tech Specs missing | Do not assume historical mapping valid | **Pending Confirmation** |
| 7 | Eligible members | `@UPDATE_ELIGIBLE_MEMBERS = 'N'` by default; most category-specific eligibility blocks are commented out | Confirm which benefits are “ever eligible” for all MA vs subset | **Pending Confirmation** |
| 8 | File output Element letter comments | Script comments label eligible as E / utilizers as F; CMS Section VIII lists H=eligible, I=utilizers, etc. | Likely comment drift only; confirm against Tech Specs file layout | **Pending Confirmation** |
| 9 | `@FULL_UPDATE = 'Y'` | Deletes all rows in `_2026` results table | Operational safety; keep logic but never run against PROD from this workspace | Documented |
| 10 | Aggregate preview (~L1861–1866) | Uses `avg()` of median columns across PBPs | Preview only when `@GENERATE_FILES != 'Y'`; still misleading | **Pending Confirmation** |

---

## Requirements cross-check (Section VIII)

| CMS Element | Description | Script support | Gap |
|---|---|---|---|
| A–B | Contract / PBP | Yes (PBP-level) | Validate vs missing PBP listing |
| C | PBP Category | Via `SBSC_Code` / `PrimaryMapping` | Tech Specs category list missing |
| D | SB name for “Other” | Partial via mapping/description | Confirm Other categories |
| E | How offered | `HowOffered` / OfferType | Confirm M/O/UF/SSBCI coding |
| F | Network type | Defaults `INN` in FINAL_QUERY | OON / visitor paths need review |
| G | Unit of utilization | `UtilizationUnit` | Confirm one unit per category |
| H | Enrollees ever eligible | Enrollment updates (flag often off) | Confirm eligibility rules |
| I | Utilized at least once | Vendor/claim updates | — |
| J | Total instances | Vendor/claim updates | — |
| K | **Median** utilizations | Often **mean** | **Gap** |
| L | Total net plan cost | PMPM + usage + overlays | Force-fit adjustments suspect |
| M–N | Payment / cost accounting | From `SBSC_Code` defaults | Confirm wording |
| O–P | OOP total / median OOP | Partial; median OOP often percentile | Element O naming vs “per utilization” column needs Tech Specs |

Report frequency: 1/Year, PBP level, period 1/1–12/31, due last Monday in February of following year. Data validation not required for this section per the Part C Requirements PDF.

---

## Dependencies on Shreya / BA

1. Provide / confirm CY2026 Technical Specifications and exact PBP Category Codes.
2. Provide 2026 PBP plan listing and confirm `PrimaryMapping` plan columns.
3. Confirm whether vendor staging tables should remain `_2025` or be loaded as `_2026` (and who owns Transportation / Meals / OTC / Activity Tracker refreshes).
4. Confirm median-utilization methodology per datasource (replace mean?).
5. Confirm whether post-processing force-fit UPDATEs (~L1609–1661) are still approved for CY2026.
6. Confirm eligibility logic (`@UPDATE_ELIGIBLE_MEMBERS`) and which categories are universal vs benefit-specific.
7. Confirm dental OldCode ↔ NewCode mappings for Liberty/Delta vs BA workbook.
8. Confirm DEV object readiness (`QNXT_Benefits_2026`, `SupplementalBenefitUtilizationAndCosts_2026`).

---

## Validation prepared

File: `04_Validation/Validation_Queries.sql` (SELECT-only; **not executed**).

Covers:

1. Required object existence (including VERIFY for vendor `_2025` vs `_2026`)
2. SBSC / PrimaryMapping category coverage vs BA workbook list
3. Contract/PBP inventory vs hardcoded plan list (pending official PBP file)
4. Reporting dates and enrollment counts
5. Vendor table availability / sample rows (`TOP`)
6. Duplicate keys, missing categories, median>total and utilizers>eligible sanity checks

---

## Recommended next implementation steps

1. Download missing ADO attachments into `01_Requirements/` (PBP listing + Technical Specifications).
2. Run **read-only** validation queries in DEV only; record outcomes here (no PHI).
3. With Shreya/BA, resolve VERIFY items (vendor table years, medians, force-fit block, plan list).
4. Apply only the next round of evidence-supported SQL edits.
5. Controlled DEV dry-run with `@FULL_UPDATE='N'` / `@GENERATE_FILES='N'` as appropriate after approvals.
6. Do not commit, push, or open a PR until instructed.

---

## Change log table (workspace)

| Date | File/Section | Change | Reason | Validation | Status |
|---|---|---|---|---|---|
| 2026-11-20 | Workspace | Initial folder structure; originals preserved | Organization | Files verified | Done |
| 2026-11-20 | Dev SQL | `@REPORTING_YEAR` → 2026 (already present in supplied script) | CY2026 period | Pending DEV | Changed / Not Tested |
| 2026-11-21 | Dev SQL L55–202, L1313 | Active `QNXT_Benefits_2025` → `_2026` | Match truncate/insert target | DEV object checks | Changed / Not Tested |
| 2026-11-21 | Dev SQL L927, L1426, L1488 | Active results joins `_2025` → `_2026` | Stop updating prior-year table | DEV after dry-run | Changed / Not Tested |
| 2026-11-21 | Validation SQL | Read-only DEV checks authored | Safety | Not executed | Not Tested |
| 2026-11-21 | This notes file | Full review documentation | US11134 | N/A | Done |
