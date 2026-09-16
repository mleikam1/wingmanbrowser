"""Render reviewable local templates; never calls gcloud or creates resources."""
import argparse
import json
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    for key in ("project", "project-number", "region", "bucket", "image"):
        parser.add_argument("--" + key, required=True)
    parser.add_argument('--currents-secret', required=True,
                        help='Existing Secret Manager name, never its value')
    parser.add_argument("--output", default="work/live-content/deploy")
    args = parser.parse_args()
    if (not re.fullmatch(r"[a-z][a-z0-9-]{4,28}[a-z0-9]", args.project)
            or args.project in ("trivia-tue", "wingman-interactive-live")):
        parser.error("Select a new dedicated project explicitly")
    if not re.fullmatch(r"[0-9]{6,20}", args.project_number):
        parser.error("Invalid project number")
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,255}', args.currents_secret):
        parser.error('Invalid existing Currents secret resource name')
    if not re.fullmatch(r"[a-z]+-[a-z]+[0-9]", args.region):
        parser.error("Invalid region")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,61}[a-z0-9]", args.bucket):
        parser.error("Invalid private bucket name")
    expected_image = re.escape(args.region + "-docker.pkg.dev/" + args.project + "/content/service")
    if not re.fullmatch(expected_image + r"@sha256:[a-f0-9]{64}", args.image):
        parser.error("Use an immutable image digest from this dedicated project's content repository")
    substitutions = {"REPLACE_NEW_DEDICATED_PROJECT_ID": args.project,
                     "REPLACE_NEW_DEDICATED_PROJECT_NUMBER": args.project_number,
                     "REPLACE_REGION": args.region, "REPLACE_PRIVATE_CONTENT_BUCKET": args.bucket,
                     "REPLACE_IMAGE_DIGEST": args.image,
                     'REPLACE_CURRENTS_SECRET_NAME': args.currents_secret}
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    for name in ("cloud-run-service.yaml", "cloud-run-job.yaml", "scheduler.json"):
        text = Path(__file__).with_name(name).read_text()
        for key, value in substitutions.items():
            text = text.replace(key, value)
        if re.search(r'REPLACE_[A-Z][A-Z_]+', text):
            raise ValueError("Unresolved deployment template")
        if name.endswith(".json"):
            json.loads(text)
        (output / name).write_text(text)


if __name__ == "__main__":
    main()
