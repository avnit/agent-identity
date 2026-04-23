gcloud services enable \
  aiplatform.googleapis.com \
  storage.googleapis.com \
  discoveryengine.googleapis.com


export GOOGLE_CLOUD_PROJECT=tf-ge-host-project5-tf-state
export GOOGLE_CLOUD_LOCATION=us-central1

export STAGING_BUCKET=tf-ge-host-project5-tf-state-tfstate-34534d
export POLICY_BUCKET=tf-ge-host-project5-tf-state-tfstate-345345d
export POLICY_PREFIX=policies/
# STAGING_BUCKET=tf-ge-host-project5-tf-state-tfstate


gcloud storage buckets create gs://$STAGING_BUCKET \
  --location=$GOOGLE_CLOUD_LOCATION \
  --uniform-bucket-level-access

gcloud storage buckets create gs://$POLICY_BUCKET \
  --location=$GOOGLE_CLOUD_LOCATION \
  --uniform-bucket-level-access

gcloud storage cp sample_policies/*.md gs://$POLICY_BUCKET/policies/

python deploy.py


gcloud storage buckets add-iam-policy-binding gs://tf-ge-host-project5-tf-state-tfstate-345345d \
  --member="principal://agents.global.org-775815895145.system.id.goog/resources/aiplatform/projects/projects/1011491835259/locations/us-central1/reasoningEngines/1071531805628170240" \
  --role="roles/storage.objectViewer"