# User Story 11134 — Findings and Change Log

## Current status
- Initial inputs received: CMS Part C reporting requirements PDF, BA requirement workbook, Shreya's SQL script.
- No SQL changes have been implemented or executed in this workspace.
- ADO screenshot shows a separate '2026 PBP - Plan name listing 052825.xlsx' attachment; download it manually and place it in 01_Requirements.
- The Part C Technical Specifications linked in ADO are a separate document and should also be downloaded into 01_Requirements.

## Review findings to validate
- `@REPORTING_YEAR` is set to 2025 in the original script.
- Script mixes _2025 and _2026 table references.
- `@FULL_UPDATE = 'Y'` can delete/rebuild target data; do not run original script as-is.
- Some code sections require median-vs-average and benefit applicability review.

## Change log
| Date | File/Section | Change | Reason | Validation | Status |
|---|---|---|---|---|---|
| 2026-11-20 | Workspace | Initial folder structure created; originals preserved | Organization | Files verified | Done |

# User Story 11134 — Development Notes

## Current Progress
- Project folder structure completed.
- CMS requirements and Excel files added.
- Original SQL preserved.
- Development SQL copy created.

## Change 001
- Reporting year: 2025 → 2026
- Status: Pending DEV validation

## Next Task
- Review all 2025 table references.
- Compare mappings against 2026 requirements.
- Prepare read-only validation queries.