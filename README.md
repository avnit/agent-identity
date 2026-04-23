# Policy Agent — ADK + Agent Identity + Gemini Enterprise

This is a sample for the CE  offsite planned on April 29th 2026 ar Austin TX 

An end-to-end reference implementation of a **Google Agent Development Kit
(ADK)** agent that:

1. Retrieves internal policy documents from **Google Cloud Storage**,
2. Authenticates using **Vertex AI Agent Engine Agent Identity** (per-agent
   SPIFFE principal — no service-account key), and
3. Is deployable as an **add-on agent in Gemini Enterprise** (the product
   formerly known as Agentspace).

The repo is intentionally small — it's meant as a working starting point you
can fork and adapt for your own policy / knowledge-base use cases.

> 🧪 **Trying this for the first time? Use the team walkthrough notebook:**
> [`notebooks/policy_agent_walkthrough.ipynb`](notebooks/policy_agent_walkthrough.ipynb).
> It runs the full flow end-to-end — env check → install → bucket setup →
> local smoke test → deploy with Agent Identity → IAM bind → remote test →
> (optional) Gemini Enterprise registration → teardown — with one
> configuration cell and copy-pasteable outputs at every step.

---

## Architecture

```
                           ┌──────────────────────────────┐
                           │     Gemini Enterprise app    │
                           │  (Discovery Engine assistant)│
                           └──────────────┬───────────────┘
                                          │ invokes (A2A)
                                          ▼
   ┌───────────────────────────────────────────────────────────────┐
   │                Vertex AI Agent Engine                         │
   │   Reasoning engine running ADK app (AdkApp)                   │
   │   identity_type = AGENT_IDENTITY  →  per-agent principal      │
   │       principal://agents.global.org-<ORG_ID>.system.id.goog/  │
   │         resources/aiplatform/projects/.../reasoningEngines/...│
   └──────────────┬──────────────────────────┬────────────────────┘
                  │ ADC (auto-signed)        │ Gemini API
                  ▼                          ▼
       ┌──────────────────────┐     ┌──────────────────┐
       │  Google Cloud Storage│     │  gemini-2.5-flash│
       │  gs://<policy-bucket>│     │  (Vertex)        │
       │  policies/*.md       │     └──────────────────┘
       └──────────────────────┘
```

Three things worth calling out:

- **No service-account JSON.** `google.auth.default()` inside the agent
  resolves to the per-agent Agent Identity principal at runtime. IAM is
  granted directly to that principal, not to a service account.
- **Tools are plain Python functions.** The ADK SDK introspects their
  type hints and docstrings to build the tool schema the model sees.
- **Gemini Enterprise is an add-on layer.** It doesn't host the agent — it
  registers a pointer (`provisionedReasoningEngine.reasoningEngine`) to your
  Agent Engine deployment and exposes it inside the Gemini Enterprise UI.

---

## Repository layout

```
agent-identity/
├── policy_agent/
│   ├── __init__.py
│   ├── agent.py          # ADK Agent definition + instruction
│   ├── gcs_tools.py      # list / search / get policy tools (ADC-backed)
│   └── config.py         # env-driven settings
├── sample_policies/      # 3 markdown policies to seed the bucket
│   ├── acceptable-use.md
│   ├── data-retention.md
│   └── remote-work.md
├── deploy.py             # deploy to Agent Engine with Agent Identity
├── register_gemini_enterprise.py  # register as Gemini Enterprise add-on agent
├── local_run.py          # local smoke test (uses your ADC)
├── remote_test.py        # live test against deployed reasoning engine
├── notebooks/
│   └── policy_agent_walkthrough.ipynb  # team walkthrough, end-to-end
├── pyproject.toml
├── .env.example
├── .gitignore
└── README.md
```

---

## Prerequisites

- **Python 3.10+** (tested on 3.13)
- **Google Cloud SDK (`gcloud`)** authenticated:
  ```bash
  gcloud auth login
  gcloud auth application-default login
  gcloud config set project <PROJECT_ID>
  ```
- A Google Cloud project with billing enabled
- Roles on that project for the user doing the deploy (typical baseline):
  - `roles/aiplatform.user`
  - `roles/storage.admin`
  - `roles/serviceusage.serviceUsageAdmin`
- (Optional) A **Gemini Enterprise app** if you intend to register the agent
  as an add-on — create one from the Gemini Enterprise section of the
  Google Cloud console.

> **Identity gotcha.** The `gcloud` CLI active account and Application
> Default Credentials (ADC) can be different accounts. The Python SDK uses
> ADC. If you see `403 storage.buckets.get` during deploy, re-run
> `gcloud auth application-default login --account=<the-right-account>`.

---

## Step 1 — Clone and install

```bash
git clone https://github.com/<you>/agent-identity.git
cd agent-identity
python -m venv .venv
source .venv/bin/activate           # Windows: .venv\Scripts\activate
pip install -e .
cp .env.example .env                # then edit values
```

`.env` variables:

| Var | Purpose |
|---|---|
| `GOOGLE_CLOUD_PROJECT`       | Project ID |
| `GOOGLE_CLOUD_LOCATION`      | Agent Engine region (e.g. `us-central1`) |
| `STAGING_BUCKET`             | GCS bucket for Agent Engine staging artifacts |
| `POLICY_BUCKET`              | GCS bucket holding policy docs |
| `POLICY_PREFIX`              | Object-name prefix inside that bucket (default `policies/`) |
| `DISPLAY_NAME`               | Human-readable name shown in console |
| `AGENT_MODEL`                | Gemini model id (default `gemini-2.5-flash`) |
| `GEMINI_ENTERPRISE_APP_ID`   | (optional) Discovery Engine app id |
| `GEMINI_ENTERPRISE_LOCATION` | (optional) `global` / `us` / `eu` |

Export them into your shell, or use `direnv` / `python-dotenv`.

---

## Step 2 — Create GCS buckets and seed policies

```bash
# Enable the APIs you'll need
gcloud services enable \
  aiplatform.googleapis.com \
  storage.googleapis.com \
  discoveryengine.googleapis.com

# Staging bucket (Agent Engine writes artifacts here during deploy)
gcloud storage buckets create gs://$STAGING_BUCKET \
  --location=$GOOGLE_CLOUD_LOCATION \
  --uniform-bucket-level-access

# Policy-docs bucket
gcloud storage buckets create gs://$POLICY_BUCKET \
  --location=$GOOGLE_CLOUD_LOCATION \
  --uniform-bucket-level-access

# Seed the sample markdown policies
gcloud storage cp sample_policies/*.md gs://$POLICY_BUCKET/policies/
```

Use `--uniform-bucket-level-access` — Agent Identity principals **cannot**
hold Legacy Bucket roles.

---

## Step 3 — Local smoke test (optional but recommended)

Exercises the GCS code path with your personal ADC. Agent Identity itself is
only minted inside Agent Engine, but this catches tool bugs before the slow
deploy cycle.

```bash
python local_run.py "what does our data retention policy say about email?"
```

---

## Step 4 — Deploy to Vertex AI Agent Engine with Agent Identity

```bash
python deploy.py
```

What `deploy.py` does:

```python
client.agent_engines.create(
    agent=AdkApp(agent=root_agent),
    config={
        "display_name": "policy-agent",
        "identity_type": types.IdentityType.AGENT_IDENTITY,  # <-- the key bit
        "extra_packages": ["policy_agent"],                  # ship source
        "requirements": [
            "google-cloud-aiplatform[adk,agent_engines]",
            "google-cloud-storage>=2.18.0",
            "google-cloud-secret-manager>=2.20.0",
            "pydantic>=2.7.0",
            "cloudpickle>=3.0.0",
        ],
        "staging_bucket": f"gs://{staging_bucket}",
        "env_vars": {
            "POLICY_BUCKET": policy_bucket,
            "POLICY_PREFIX": policy_prefix,
        },
    },
)
```

Deployment takes **5–15 minutes** while Agent Engine builds the container.

**Output you care about:**
- `reasoningEngine` — full resource path (copy it)
- After deploy, read the agent's `effectiveIdentity` — this becomes the
  `principal://...` string you grant IAM to

```bash
# Grab principal from the reasoning engine resource
curl -s \
  -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  "https://$GOOGLE_CLOUD_LOCATION-aiplatform.googleapis.com/v1beta1/$REASONING_ENGINE" \
  | python -c 'import sys,json; d=json.load(sys.stdin); print("principal://" + d["spec"]["effectiveIdentity"])'
```

---

## Step 5 — Grant the agent principal access to GCS

```bash
AGENT_PRINCIPAL='principal://agents.global.org-<ORG_ID>.system.id.goog/resources/aiplatform/projects/<PROJECT_NUMBER>/locations/<LOCATION>/reasoningEngines/<ENGINE_ID>'

principal://agents.global.org-775815895145.system.id.goog/resources/aiplatform/projects/projects/1011491835259/locations/us-central1/reasoningEngines/1071531805628170240

gcloud storage buckets add-iam-policy-binding gs://$POLICY_BUCKET \
  --member="$AGENT_PRINCIPAL" \
  --role="roles/storage.objectViewer"
```

Recommended project-level baseline (from the Agent Identity docs):

| Role | Why |
|------|-----|
| `roles/aiplatform.expressUser`        | inference, sessions, memory |
| `roles/serviceusage.serviceUsageConsumer` | quota/SDK |
| `roles/logging.logWriter`             | logs |
| `roles/monitoring.metricWriter`       | metrics |

---

## Step 6 — Live test against the deployed engine

```bash
REASONING_ENGINE=projects/<NUM>/locations/<LOC>/reasoningEngines/<ID> \
python remote_test.py "What's our remote work policy on equipment stipend?"
```

Expected: the agent calls `search_policies` → `get_policy_document`, reads
`policies/remote-work.md` from GCS via its Agent Identity principal, and
cites the doc name in the answer.

---

## Step 7 — Register as an add-on agent in Gemini Enterprise

Prerequisite: a Gemini Enterprise app already exists in the same project
and its region is compatible with the Agent Engine region (`global` matches
any region; `us` matches `us-*`; `eu` matches `europe-*`).

```bash
export GEMINI_ENTERPRISE_APP_ID=<your-app-id>
export GEMINI_ENTERPRISE_LOCATION=global           # or us / eu
export REASONING_ENGINE=projects/<NUM>/locations/<LOC>/reasoningEngines/<ID>

python register_gemini_enterprise.py
```

Under the hood, this POSTs to Discovery Engine:

```
POST https://{ENDPOINT_LOCATION-}discoveryengine.googleapis.com/v1alpha/
     projects/{PROJECT}/locations/global/collections/default_collection/
     engines/{APP_ID}/assistants/default_assistant/agents
```

with body:

```json
{
  "displayName": "Policy Assistant",
  "description": "Answers questions about internal policies from GCS.",
  "adkAgentDefinition": {
    "provisionedReasoningEngine": {
      "reasoningEngine": "projects/.../reasoningEngines/..."
    }
  }
}
```

After success, the agent shows up in the Gemini Enterprise web app under
"Custom agent via Agent Engine" and users can select it per-query.

---

## Teardown

```bash
# Delete the reasoning engine (stops ongoing Agent Engine billing)
curl -s -X DELETE \
  -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  "https://$GOOGLE_CLOUD_LOCATION-aiplatform.googleapis.com/v1beta1/$REASONING_ENGINE?force=true"

# Clean the now-stale IAM binding
gcloud storage buckets remove-iam-policy-binding gs://$POLICY_BUCKET \
  --member="$AGENT_PRINCIPAL" \
  --role="roles/storage.objectViewer"

# Delete the buckets (optional — empty buckets cost ~nothing)
gcloud storage rm -r gs://$STAGING_BUCKET
gcloud storage rm -r gs://$POLICY_BUCKET
```

---

## Troubleshooting

Things that bit us in real deploys. Each entry is a concrete error + fix.

### `403 storage.buckets.get access` during `deploy.py`
Your `gcloud` CLI identity and ADC identity are different. Run:
```bash
gcloud auth application-default login --account=<account-that-owns-the-buckets>
```

### `400 FAILED_PRECONDITION: Environment variable name 'GOOGLE_CLOUD_PROJECT' is reserved`
Don't set `GOOGLE_CLOUD_PROJECT` or `GOOGLE_CLOUD_LOCATION` inside
`config.env_vars` — Agent Engine injects them automatically. Our `deploy.py`
is already correct.

### `ModuleNotFoundError: No module named 'policy_agent'` in reasoning-engine logs
The local `policy_agent/` source didn't get shipped to the container. Make
sure `config` includes:
```python
"extra_packages": ["policy_agent"],
```

### `Pickle load failed: Missing module`
Same root cause as above, or a transitive dep that's imported at module
scope but missing from `requirements`. Add it to the `requirements` list in
`deploy.py`. `pydantic` and `cloudpickle` in particular are worth listing
explicitly.

### Reasoning engine created but unreachable
Fetch logs:
```bash
gcloud logging read \
  'resource.type="aiplatform.googleapis.com/ReasoningEngine" AND
   resource.labels.reasoning_engine_id="<ID>"' \
  --project=<PROJECT> --limit=50 --freshness=30m
```
Most startup failures surface as Python tracebacks from uvicorn.

### Gemini Enterprise registration: location mismatch
`us`-region app cannot point at a `europe-*` Agent Engine. Either redeploy
the engine into a matching region or use a `global` Gemini Enterprise app.

---

## References

- [Agent Identity in Vertex AI Agent Engine](https://docs.cloud.google.com/agent-builder/agent-engine/agent-identity)
- [Register and manage ADK agents with Gemini Enterprise](https://docs.cloud.google.com/gemini/enterprise/docs/register-and-manage-an-adk-agent)
- [Google ADK docs](https://google.github.io/adk-docs/)
- [Vertex AI Agent Engine — Deploy](https://cloud.google.com/vertex-ai/generative-ai/docs/agent-engine/deploy)
- [Agent Engine troubleshooting](https://cloud.google.com/vertex-ai/generative-ai/docs/agent-engine/troubleshooting/deploy)

## License

MIT — see [LICENSE](LICENSE).
