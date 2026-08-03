# Google Ads API - Internal design document

**Company:** Automatic73 / Oden Food  
**Date:** 2026-08-02  
**GCP project ID:** oden-pos-500518  
**GCP project number:** 707494054188  
**Google Ads manager (MCC):** 319-882-1992  
**Contact:** javi@automatic73.com

## 1. Business model

Oden Food (oden.food) is a restaurant point-of-sale and operations SaaS for
Mexico (mobile waiter app, KDS, tables, payments, online ordering).
Automatic73 builds and operates the product. Paid acquisition uses Google Ads
for restaurant-owner demand generation.

## 2. API tool we are building

An internal, read-only analytics assistant for engineering and ops:

- Official Google Ads MCP server (`googleads/google-ads-mcp`) to list
  accessible customers and run GAQL reporting queries.
- Official Google Analytics MCP server (`googleanalytics/google-analytics-mcp`)
  for traffic, events, funnels, and realtime for property `oden-food`.
- Hosted inside Cursor and Claude Code on employee machines only.
- Credentials distributed via Doppler (`automatic73-ops` by default), no public
  product, no client-facing UI, no write/mutate calls.

## 3. Intended audience

Internal users only: Automatic73 / Oden employees (engineering, ops, growth).
Not available to the general public or restaurant customers.

## 4. Architecture (high level)

```text
Employee IDE (Cursor / Claude)
    -> local MCP (stdio)
        -> Google Ads API (developer token + OAuth ADC, read-only)
        -> Google Analytics Data/Admin API (OAuth ADC, read-only)
Secrets: Doppler (token, OAuth desktop client JSON, project IDs)
```

## 5. Access control

- Developer token stored in Doppler, not committed to git.
- OAuth Desktop client in GCP project `oden-pos-500518` (number `707494054188`).
- Each employee authenticates with Application Default Credentials
  (analytics.readonly + adwords scopes).
- MCC login-customer-id `3198821992` for manager hierarchy.

## 6. Permissible use

Reporting and diagnosis of our own Google Ads and GA4 properties to improve
acquisition and funnel quality. No App Conversion Tracking / Remarketing API
use planned. No resale of API access.
