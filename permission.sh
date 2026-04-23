gcloud storage buckets add-iam-policy-binding gs://tf-ge-host-project5-tf-state-tfstate-345345d \
  --member="principal://agents.global.org-775815895145.system.id.goog/resources/aiplatform/projects/projects/1011491835259/locations/us-central1/reasoningEngines/1071531805628170240" \
  --role="roles/storage.objectViewer"
