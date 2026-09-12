# Optional deployment templates — not deployed

The templates target a **new dedicated Google Cloud project** selected by the owner.
Do not use the CLI default project, `trivia-tue`, or the unrelated
`wingman-interactive-live` project. Creating a project, enabling APIs, attaching
billing, making the service public and creating paid resources require the owner's
separate approval. No such commands were run for this implementation.

After that approval, an operator must select a new project explicitly on every
command, build `backend/Dockerfile` using the repository root as context, pin the
resulting image digest, replace every `REPLACE_*` value, and review cost limits.
These YAML/JSON files are reviewable configuration, not a deployment script.

## Commands for the operator after separate deployment approval

These are examples to review and adapt, **not commands executed for this task**.
First have the owner create/choose a new dedicated project and approve its billing
and budget. Supply that project's identifiers below; no command uses the current
CLI default. The placeholders intentionally fail until replaced. The operator
also needs permissions to enable APIs, create the named identities and storage,
act as the runtime accounts, and deploy Cloud Run in the new project.

```sh
WM_PROJECT='REPLACE_NEW_DEDICATED_PROJECT_ID'
WM_PROJECT_NUMBER='REPLACE_NEW_DEDICATED_PROJECT_NUMBER'
WM_REGION='us-central1'
WM_BUCKET='REPLACE_GLOBALLY_UNIQUE_PRIVATE_BUCKET'
WM_IMAGE_TAG="${WM_REGION}-docker.pkg.dev/${WM_PROJECT}/content/service:live-content-v1"

gcloud services enable run.googleapis.com cloudscheduler.googleapis.com storage.googleapis.com artifactregistry.googleapis.com --project "$WM_PROJECT"
gcloud artifacts repositories create content --repository-format=docker --location "$WM_REGION" --project "$WM_PROJECT"
gcloud iam service-accounts create content-reader --project "$WM_PROJECT"
gcloud iam service-accounts create content-writer --project "$WM_PROJECT"
gcloud iam service-accounts create content-scheduler --project "$WM_PROJECT"
gcloud storage buckets create "gs://${WM_BUCKET}" --location "$WM_REGION" --uniform-bucket-level-access --public-access-prevention --project "$WM_PROJECT"
gcloud storage buckets update "gs://${WM_BUCKET}" --no-versioning --clear-soft-delete --project "$WM_PROJECT"
gcloud iam roles create wingmanContentReader --permissions=storage.objects.get --stage=GA --project "$WM_PROJECT"
gcloud iam roles create wingmanContentWriter --permissions=storage.objects.get,storage.objects.create,storage.objects.delete --stage=GA --project "$WM_PROJECT"
gcloud storage buckets add-iam-policy-binding "gs://${WM_BUCKET}" --member="serviceAccount:content-reader@${WM_PROJECT}.iam.gserviceaccount.com" --role="projects/${WM_PROJECT}/roles/wingmanContentReader" --project "$WM_PROJECT"
gcloud storage buckets add-iam-policy-binding "gs://${WM_BUCKET}" --member="serviceAccount:content-writer@${WM_PROJECT}.iam.gserviceaccount.com" --role="projects/${WM_PROJECT}/roles/wingmanContentWriter" --project "$WM_PROJECT"

# Build locally only when Docker is already installed and its use is approved.
# .dockerignore sends only backend code/config/dependencies and the policy asset.
gcloud auth configure-docker "${WM_REGION}-docker.pkg.dev" --project "$WM_PROJECT"
docker build -f backend/Dockerfile -t "$WM_IMAGE_TAG" .
docker push "$WM_IMAGE_TAG"
gcloud artifacts docker images describe "$WM_IMAGE_TAG" --format='value(image_summary.digest)' --project "$WM_PROJECT"
WM_DIGEST='REPLACE_WITH_SHA256_DIGEST_FROM_PREVIOUS_COMMAND'
WM_IMAGE="${WM_REGION}-docker.pkg.dev/${WM_PROJECT}/content/service@${WM_DIGEST}"
python3 backend/deploy/render.py --project "$WM_PROJECT" --project-number "$WM_PROJECT_NUMBER" --region "$WM_REGION" --bucket "$WM_BUCKET" --image "$WM_IMAGE"

# Inspect the rendered local YAML/JSON before the following mutations.
gcloud run jobs replace work/live-content/deploy/cloud-run-job.yaml --region "$WM_REGION" --project "$WM_PROJECT"
gcloud run services replace work/live-content/deploy/cloud-run-service.yaml --region "$WM_REGION" --project "$WM_PROJECT"
gcloud run jobs add-iam-policy-binding wingman-content-ingest --member="serviceAccount:content-scheduler@${WM_PROJECT}.iam.gserviceaccount.com" --role=roles/run.invoker --region "$WM_REGION" --project "$WM_PROJECT"
gcloud run jobs execute wingman-content-ingest --wait --region "$WM_REGION" --project "$WM_PROJECT"

gcloud scheduler jobs create http wingman-content-ingest --location "$WM_REGION" --schedule='*/30 * * * *' --time-zone=Etc/UTC --uri="https://run.googleapis.com/v2/projects/${WM_PROJECT}/locations/${WM_REGION}/jobs/wingman-content-ingest:run" --http-method=POST --message-body='{}' --headers=Content-Type=application/json --oauth-service-account-email="content-scheduler@${WM_PROJECT}.iam.gserviceaccount.com" --oauth-token-scope=https://www.googleapis.com/auth/cloud-platform --max-retry-attempts=0 --attempt-deadline=180s --project "$WM_PROJECT"

# Publication is a distinct approval step; only the read service becomes public.
gcloud run services add-iam-policy-binding wingman-content-read --member=allUsers --role=roles/run.invoker --region "$WM_REGION" --project "$WM_PROJECT"
gcloud run services describe wingman-content-read --format='value(status.url)' --region "$WM_REGION" --project "$WM_PROJECT"
```

For later updates, rebuild/push a new reviewed image, obtain its digest, rerender
and use the same `gcloud run jobs replace` / `gcloud run services replace` commands.
Update the existing schedule rather than creating a duplicate:

```sh
gcloud scheduler jobs update http wingman-content-ingest --location "$WM_REGION" --schedule='*/30 * * * *' --time-zone=Etc/UTC --uri="https://run.googleapis.com/v2/projects/${WM_PROJECT}/locations/${WM_REGION}/jobs/wingman-content-ingest:run" --http-method=POST --message-body='{}' --headers=Content-Type=application/json --oauth-service-account-email="content-scheduler@${WM_PROJECT}.iam.gserviceaccount.com" --oauth-token-scope=https://www.googleapis.com/auth/cloud-platform --max-retry-attempts=0 --attempt-deadline=180s --project "$WM_PROJECT"
```

The supplied `scheduler.json` is the equivalent reviewable Cloud Scheduler API
request body. It is not an HTTP handler in the public service. Smoke-test the
final approved HTTPS endpoint and source health before configuring release apps.
Budget/log-retention settings remain explicit operator work: do not guess a
billing account, notification recipient or acceptable budget.

Use one private regional Cloud Storage bucket, uniform bucket-level access, public
access prevention, no object versioning, and soft delete disabled if deletion of
revoked text must remove prior generations immediately. Do not expose the stored
bundle: it includes source validators and administrative held-item diagnostics.
The read service serves only the common `snapshot` member. The current object is
replaced using a generation precondition, so overlapping jobs cannot overwrite a
newer ingest. Keep ingestion at one task and no platform retry: source backoff is
already persisted. An administrator can invoke the job again, but sources still
respect their persisted refresh times.

Least-privilege identities:

| Identity | Access |
| --- | --- |
| `content-reader` | `storage.objects.get` on the dedicated content bucket only |
| `content-writer` | `storage.objects.get/create/delete` on that bucket only (replace the one object) |
| `content-scheduler` | `roles/run.invoker` on the ingestion job only; no storage rights |
| Public clients | GET service invocation only after explicit publication approval; no job or bucket rights |

Scheduler calls the Cloud Run Jobs API with an OAuth service-account token. It does
not call a publicly reachable ingestion route. The public service has no ingestion
route, accepts no topic or URL parameter, and has no publisher-fetch credentials.
Cloud Run Job scheduling is documented by Google:
https://docs.cloud.google.com/run/docs/execute/jobs-on-schedule

Configure budget alerts separately; they are alerts, not a hard spending cap. The
service template limits instances to 2 at both service and revision levels and
concurrency to 32, and the ingestion
job has a 300-second timeout, one task, and zero platform retries. Source-level
limits remain in code. Review Cloud Run request/egress logs and storage access
logs: platform infrastructure can still process client IP metadata even though
the application writes no access logs or user preferences. Keep operational logs
short-lived and never add request query, IP, article-history or device identifiers.

Cloud dependencies require Python >=3.10; the image uses Python 3.13. The local
core service/tests also run with the preinstalled Python 3.9. Docker/GCS deployment
was not exercised against live infrastructure; local storage, mocked transport,
real publisher ingestion and the GET service were exercised.

The service-level cap avoids multiplying the revision cap across traffic splits;
the platform can still transiently exceed limits. Neither is a hard billing cap.
No Docker executable or daemon socket was available in this workspace, so the
image was not built and no desktop app or daemon was installed or started.
