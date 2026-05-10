# Model and Billing Policy

## Model exposure

Employees see real model names. Model access is still controlled by New API model limits.

## Initial model tiers

Use three tiers:

```text
basic
premium
experimental
```

## Basic tier

Purpose:

- daily coding
- low-cost chat
- normal development

Policy:

- available to all active employees
- can consume monthly free quota

## Premium tier

Purpose:

- high-quality coding
- long-context work
- expensive reasoning

Policy:

- enabled per employee or department
- requires balance after free quota
- alert on daily spend spikes

## Experimental tier

Purpose:

- new models
- unstable providers
- temporary tests

Policy:

- low daily quota
- removable without notice
- not used for production automation

## Manual balance flow

```text
employee requests balance
admin records internal payment or approval
admin adjusts New API user balance
admin records amount, operator, timestamp, and reason
admin sends updated balance confirmation to employee
```

## Cost control

Minimum controls:

- every employee has a separate New API user
- every token belongs to one employee
- token model limits are enabled
- balance exhaustion blocks usage
- daily user spend is reviewed during the first 7 days
- employee usage/balance reports are handled by admin until self-service portal is isolated
