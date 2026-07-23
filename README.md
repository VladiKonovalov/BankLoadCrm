# Bank CRM

Salesforce DX project for a bank CRM that manages customers and loan requests (Tasks, audit, Flow, LWC, and optional external approval integration).

Design documents live in [`docs/`](docs/). The assignment brief is [`project_task.md`](project_task.md).

## Prerequisites

- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`)
- A Dev Hub org you can authenticate against
- Node.js 18+ (for LWC Jest)

## Authenticate

```bash
sf org login web --set-default-dev-hub --alias DevHub
```

## Create a scratch org

```bash
sf org create scratch --definition-file config/project-scratch-def.json --alias BankCRM --set-default --duration-days 7
```

## Deploy source

Production metadata:

```bash
sf project deploy start --source-dir force-app/main
```

Production + Apex tests package directory:

```bash
sf project deploy start --source-dir force-app/main --source-dir force-app/test
```

Assign a role permission set to the default scratch user (needed for FLS on optional fields during manual checks):

```bash
sf org assign permset --name Bank_CRM_Loan_Officer
```

Do not assign `Bank_CRM_Approver` to the same user used for Apex test runs unless you intend to; it grants `Reopen_Final_Loan_Decision` and changes terminal-status validation behavior.
## Run tests

LWC Jest (after `npm install`):

```bash
npm install
npm test
```

Apex (in the default scratch org) — full local suite:

```bash
sf project deploy start --source-dir force-app/main --source-dir force-app/test
sf apex run test --test-level RunLocalTests --result-format human --code-coverage --wait 60
```

Targeted Part E suites (M13):

```bash
sf apex run test --class-names LoanRequestBulkTest,LoanRequestSecurityTest,LoanRequestNegativeTest,LoanApprovalIntegrationContractsTest --code-coverage --result-format human --wait 30
```

Archive a coverage report for submission narrative:

```bash
sf apex get test --test-run-id <runId> --code-coverage --result-format human
```

Coverage goal: **≥ 90%** aggregate on assignment Apex (stretch 92%+). Do not use `SeeAllData=true` or live callouts.
## Project layout

| Path | Purpose |
|---|---|
| `force-app/main` | Deployable production metadata |
| `force-app/test` | Apex test classes (separate package directory) |
| `config/` | Scratch org definition (no credentials) |
| `manifest/` | Explicit deploy/retrieve package manifests |
| `docs/` | Design and submission documentation |
| `scripts/` | Optional Apex/SOQL smoke scripts |

See [`docs/project-structure.md`](docs/project-structure.md) for the full catalog and [`docs/implementation-plan.md`](docs/implementation-plan.md) for the build roadmap.
