# JTC Property Services - Frozen Stitch Reference

This folder contains the 18 approved frozen Stitch HTML screen references plus DESIGN.md.

## Authority rules

- These HTML files are VISUAL REFERENCES only.
- Do not use the raw Stitch HTML as production application code.
- Reproduce the approved layouts, visual hierarchy, interaction states, forms, tables, navigation and branding in Next.js / React / TypeScript / Tailwind.
- Do not redesign, simplify, reinterpret or silently change the frozen UI.
- Production data must come from Supabase.
- Database architecture, RLS architecture and the Master Developer Handover control permissions, workflows and data behavior.
- Demo names, dates, properties, addresses, prices and photos inside these HTML references are sample visual content only.
- If a Stitch visual conflicts with an approved architecture/security rule, preserve the visual intent and report the conflict rather than weakening the architecture.

## Files

- `onboarding-flow.html`
- `owner-connection-approval.html`
- `company-settings.html`
- `branding-settings.html`
- `staff-management.html`
- `documents-history.html`
- `maintenance-job-detail.html`
- `preventive-maintenance.html`
- `issue-dashboard.html`
- `asset-detail.html`
- `quote-comparison.html`
- `inspection-review.html`
- `inspection-checklist.html`
- `create-issue.html`
- `owner-portal.html`
- `home-dashboard.html`
- `properties-list.html`
- `property-detail.html`

- `DESIGN.md`

## First implementation slice

JTC ADMIN -> Property -> Owner -> Inspection -> Results / Photos / Meter Readings -> Draft Report -> FINAL Published Report -> Owner Portal.

The first slice should primarily reference:
- home-dashboard.html
- properties-list.html
- property-detail.html
- inspection-checklist.html
- inspection-review.html
- owner-portal.html

Other screens remain frozen references for later implementation phases.
