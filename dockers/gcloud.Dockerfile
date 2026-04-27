# syntax = docker/dockerfile:latest
FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:latest
RUN gcloud config set core/disable_usage_reporting true \
    && gcloud config set component_manager/disable_update_check true \
    && gcloud config set metrics/environment github_docker_image \
    && apt-get update -y \
    && apt-get install -y google-cloud-cli-gke-gcloud-auth-plugin kubectl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && gcloud --version
