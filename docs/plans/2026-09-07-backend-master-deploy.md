# Backend Master Deploy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy the backend to the production Compose host after backend-related pushes to `main` or `master`, without rebuilding the backend for client-only changes.

**Architecture:** GitHub Actions remains the orchestration layer. Backend CI and deploy workflows use path filters so iOS-only changes do not run backend image builds. Deployment connects to the existing VDS checkout over SSH and runs the documented Docker Compose deployment sequence.

**Tech Stack:** GitHub Actions, SSH, Docker Compose, Go backend, existing `deploy/compose.yaml`.

---

### Task 1: Restrict Backend CI Scope

**Files:**
- Modify: `.github/workflows/backend.yml`

**Step 1: Add path filters**

Limit pull request and push triggers to backend/deploy/workflow files.

**Step 2: Verify YAML syntax**

Run a local YAML parser against `.github/workflows/backend.yml`.

### Task 2: Add Production Backend Deploy Workflow

**Files:**
- Create: `.github/workflows/deploy-backend.yml`

**Step 1: Add trigger**

Run on push to `main` and `master` only when backend/deploy/deploy-workflow files change.

**Step 2: Add SSH deployment**

Install the deploy SSH key, verify required secrets, update the existing server checkout to the pushed SHA, set `SPENDLY_API_TAG`, build `api` and `migrate`, run migrations, start `api` and `caddy`, and run the smoke test.

**Step 3: Verify YAML syntax**

Run a local YAML parser against `.github/workflows/deploy-backend.yml`.

### Task 3: Document Operator Setup

**Files:**
- Modify: `docs/deployment.md`

**Step 1: Add GitHub Actions deployment section**

Document required repository secrets and the server checkout prerequisites.

**Step 2: Verify the final diff**

Review `git diff --check` and the changed files before finishing.
